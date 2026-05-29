#!/usr/bin/env bash
# =============================================================================
# Script     : provision-infra.sh
# Phase      : 1 – Script 1 of 2
# Run From   : LOCAL WORKSTATION
# Purpose    : Provision all AWS Security Groups and EC2 instances for the
#              Roboshop multi-tier microservices application.
# Author     : Roboshop Automation Framework
# =============================================================================
set -euo pipefail

# ─── COLOUR LOGGING ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[INFO ]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK   ]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}  $*" >&2; }

# ─── NETWORK CONSTANTS ───────────────────────────────────────────────────────
VPC_ID="vpc-06f14609690a23709"
AMI_ID="ami-0220d79f3f480ecf5"
INSTANCE_TYPE="t3.micro"
SUBNET_ID="subnet-04a504e7b57258a53"
MY_IP="49.204.26.231"

# ─── SERVICE LIST ────────────────────────────────────────────────────────────
# Format: "name:port:protocol"
# port=0 means no dedicated inbound rule on the service's own SG (e.g. dispatch)
SERVICES=(
  "frontend:80:tcp"
  "catalogue:8080:tcp"
  "user:8080:tcp"
  "cart:8080:tcp"
  "shipping:8080:tcp"
  "payment:8080:tcp"
  "dispatch:0:tcp"
  "mongodb:27017:tcp"
  "redis:6379:tcp"
  "mysql:3306:tcp"
  "rabbitmq:5672:tcp"
)

# ─── STATE FILE (idempotency) ─────────────────────────────────────────────────
STATE_FILE="/tmp/roboshop_provision_state.env"
touch "${STATE_FILE}"
source "${STATE_FILE}" 2>/dev/null || true

# Helper to persist a variable to the state file
save_state() {
  local key="$1" val="$2"
  # Remove old entry if present, then append
  grep -v "^${key}=" "${STATE_FILE}" > "${STATE_FILE}.tmp" || true
  mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  echo "${key}=${val}" >> "${STATE_FILE}"
}

# ─── PREREQUISITE CHECK ───────────────────────────────────────────────────────
log_info "Checking prerequisites (aws CLI, jq) ..."
command -v aws  >/dev/null 2>&1 || { log_error "aws CLI not found. Install it first."; exit 1; }
command -v jq   >/dev/null 2>&1 || { log_error "jq not found. Install it first.";      exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { log_error "AWS credentials are not configured / expired."; exit 1; }
log_success "Prerequisites OK"

# =============================================================================
# STEP 1 – COMMON SSH SECURITY GROUP
# =============================================================================
log_info "════════ STEP 1: Common SSH Security Group ════════"

if [[ -z "${SG_SSH_ID:-}" ]]; then
  # Check if it already exists
  EXISTING_SSH_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=roboshop-common-ssh-sg" \
              "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

  if [[ "${EXISTING_SSH_SG}" == "None" || -z "${EXISTING_SSH_SG}" ]]; then
    SG_SSH_ID=$(aws ec2 create-security-group \
      --group-name "roboshop-common-ssh-sg" \
      --description "Roboshop: Common SSH access from bastion/workstation" \
      --vpc-id "${VPC_ID}" \
      --query "GroupId" --output text)
    log_success "Created common SSH SG: ${SG_SSH_ID}"

    # Allow SSH from MY_IP
    aws ec2 authorize-security-group-ingress \
      --group-id "${SG_SSH_ID}" \
      --protocol tcp --port 22 \
      --cidr "${MY_IP}/32"
    log_success "Authorized SSH from ${MY_IP}/32 on ${SG_SSH_ID}"
  else
    SG_SSH_ID="${EXISTING_SSH_SG}"
    log_warn "Common SSH SG already exists: ${SG_SSH_ID} – reusing."
  fi
  save_state "SG_SSH_ID" "${SG_SSH_ID}"
else
  log_warn "Common SSH SG already in state: ${SG_SSH_ID} – skipping creation."
fi

# =============================================================================
# STEP 2 – DEDICATED SECURITY GROUPS FOR EACH SERVICE
# =============================================================================
log_info "════════ STEP 2: Service-Dedicated Security Groups ════════"

declare -A SG_IDS  # name -> sg-id map built at runtime

for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  STATE_KEY="SG_${SVC_NAME^^}_ID"

  if [[ -n "${!STATE_KEY:-}" ]]; then
    SG_IDS["${SVC_NAME}"]="${!STATE_KEY}"
    log_warn "SG for ${SVC_NAME} already in state: ${!STATE_KEY} – reusing."
    continue
  fi

  SG_NAME="roboshop-${SVC_NAME}-sg"

  EXISTING=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
              "Name=vpc-id,Values=${VPC_ID}" \
    --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || echo "None")

  if [[ "${EXISTING}" == "None" || -z "${EXISTING}" ]]; then
    SG_ID=$(aws ec2 create-security-group \
      --group-name "${SG_NAME}" \
      --description "Roboshop: Dedicated SG for ${SVC_NAME}" \
      --vpc-id "${VPC_ID}" \
      --query "GroupId" --output text)
    log_success "Created SG ${SG_NAME}: ${SG_ID}"
  else
    SG_ID="${EXISTING}"
    log_warn "SG ${SG_NAME} already exists: ${SG_ID} – reusing."
  fi

  SG_IDS["${SVC_NAME}"]="${SG_ID}"
  save_state "${STATE_KEY}" "${SG_ID}"
done

# Reload state so all SG_IDS are populated after potential rerun
source "${STATE_FILE}"
for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  STATE_KEY="SG_${SVC_NAME^^}_ID"
  SG_IDS["${SVC_NAME}"]="${!STATE_KEY}"
done

# =============================================================================
# STEP 3 – INBOUND INGRESS RULES (Cross-SG)
# =============================================================================
log_info "════════ STEP 3: Cross-SG Ingress Rules ════════"

# Helper: authorise a rule idempotently (silently skip if duplicate)
auth_sg_rule() {
  local sg_id="$1" proto="$2" port="$3" source="$4"
  aws ec2 authorize-security-group-ingress \
    --group-id "${sg_id}" \
    --protocol "${proto}" \
    --port "${port}" \
    --source-group "${source}" 2>/dev/null \
    && log_success "  Authorised ${proto}/${port} on ${sg_id} from SG ${source}" \
    || log_warn  "  Rule ${proto}/${port} on ${sg_id} from ${source} already exists – skipping."
}

auth_sg_cidr() {
  local sg_id="$1" proto="$2" port="$3" cidr="$4"
  aws ec2 authorize-security-group-ingress \
    --group-id "${sg_id}" \
    --protocol "${proto}" \
    --port "${port}" \
    --cidr "${cidr}" 2>/dev/null \
    && log_success "  Authorised ${proto}/${port} on ${sg_id} from ${cidr}" \
    || log_warn  "  Rule ${proto}/${port} on ${sg_id} from ${cidr} already exists – skipping."
}

# frontend: Port 80 from 0.0.0.0/0
auth_sg_cidr "${SG_IDS[frontend]}"  tcp 80 "0.0.0.0/0"

# catalogue: Port 8080 from frontend & cart
auth_sg_rule "${SG_IDS[catalogue]}" tcp 8080 "${SG_IDS[frontend]}"
auth_sg_rule "${SG_IDS[catalogue]}" tcp 8080 "${SG_IDS[cart]}"

# user: Port 8080 from frontend & payment
auth_sg_rule "${SG_IDS[user]}"      tcp 8080 "${SG_IDS[frontend]}"
auth_sg_rule "${SG_IDS[user]}"      tcp 8080 "${SG_IDS[payment]}"

# cart: Port 8080 from frontend, shipping & payment
auth_sg_rule "${SG_IDS[cart]}"      tcp 8080 "${SG_IDS[frontend]}"
auth_sg_rule "${SG_IDS[cart]}"      tcp 8080 "${SG_IDS[shipping]}"
auth_sg_rule "${SG_IDS[cart]}"      tcp 8080 "${SG_IDS[payment]}"

# shipping: Port 8080 from frontend
auth_sg_rule "${SG_IDS[shipping]}"  tcp 8080 "${SG_IDS[frontend]}"

# payment: Port 8080 from frontend
auth_sg_rule "${SG_IDS[payment]}"   tcp 8080 "${SG_IDS[frontend]}"

# dispatch: no inbound rule (outbound consumer only)
log_info "  dispatch – no inbound rule required (AMQP consumer only)"

# mongodb: Port 27017 from catalogue & user
auth_sg_rule "${SG_IDS[mongodb]}"   tcp 27017 "${SG_IDS[catalogue]}"
auth_sg_rule "${SG_IDS[mongodb]}"   tcp 27017 "${SG_IDS[user]}"

# redis: Port 6379 from user & cart
auth_sg_rule "${SG_IDS[redis]}"     tcp 6379 "${SG_IDS[user]}"
auth_sg_rule "${SG_IDS[redis]}"     tcp 6379 "${SG_IDS[cart]}"

# mysql: Port 3306 from shipping
auth_sg_rule "${SG_IDS[mysql]}"     tcp 3306 "${SG_IDS[shipping]}"

# rabbitmq: Port 5672 from payment & dispatch
auth_sg_rule "${SG_IDS[rabbitmq]}"  tcp 5672 "${SG_IDS[payment]}"
auth_sg_rule "${SG_IDS[rabbitmq]}"  tcp 5672 "${SG_IDS[dispatch]}"

log_success "All ingress rules applied."

# =============================================================================
# STEP 4 – EC2 INSTANCE PROVISIONING
# =============================================================================
log_info "════════ STEP 4: EC2 Instance Provisioning ════════"

declare -A INSTANCE_IDS

for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  STATE_KEY="INSTANCE_${SVC_NAME^^}_ID"

  if [[ -n "${!STATE_KEY:-}" ]]; then
    INSTANCE_IDS["${SVC_NAME}"]="${!STATE_KEY}"
    log_warn "Instance for ${SVC_NAME} already in state: ${!STATE_KEY} – skipping launch."
    continue
  fi

  SVC_SG="${SG_IDS[${SVC_NAME}]}"

  log_info "Launching EC2 for ${SVC_NAME} with SGs: [${SG_SSH_ID}, ${SVC_SG}] ..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id       "${AMI_ID}" \
    --instance-type  "${INSTANCE_TYPE}" \
    --subnet-id      "${SUBNET_ID}" \
    --security-group-ids "${SG_SSH_ID}" "${SVC_SG}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-${SVC_NAME}}]" \
    --query "Instances[0].InstanceId" --output text)

  log_success "Launched ${SVC_NAME}: ${INSTANCE_ID}"
  INSTANCE_IDS["${SVC_NAME}"]="${INSTANCE_ID}"
  save_state "${STATE_KEY}" "${INSTANCE_ID}"
done

# Reload state
source "${STATE_FILE}"
for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  STATE_KEY="INSTANCE_${SVC_NAME^^}_ID"
  INSTANCE_IDS["${SVC_NAME}"]="${!STATE_KEY}"
done

# =============================================================================
# STEP 5 – WAIT FOR ALL INSTANCES TO PASS STATUS CHECKS (2/2)
# =============================================================================
log_info "════════ STEP 5: Waiting for all instances – 2/2 status checks ════════"
log_warn "This may take 3–5 minutes. Please wait ..."

ALL_IDS=()
for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  ALL_IDS+=("${INSTANCE_IDS[${SVC_NAME}]}")
done

aws ec2 wait instance-status-ok --instance-ids "${ALL_IDS[@]}"
log_success "All 11 instances are healthy (2/2 status checks passed)."

# =============================================================================
# SUMMARY TABLE
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  PROVISIONING COMPLETE – INSTANCE SUMMARY${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
printf "%-15s %-22s %-25s\n" "SERVICE" "INSTANCE_ID" "DEDICATED_SG_ID"
printf "%-15s %-22s %-25s\n" "-------" "-----------" "---------------"
for svc_entry in "${SERVICES[@]}"; do
  SVC_NAME="${svc_entry%%:*}"
  printf "%-15s %-22s %-25s\n" "${SVC_NAME}" "${INSTANCE_IDS[${SVC_NAME}]}" "${SG_IDS[${SVC_NAME}]}"
done
echo ""
log_success "State saved to: ${STATE_FILE}"
log_info  "Next step → Run: ./update-dns.sh"
