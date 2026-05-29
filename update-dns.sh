#!/usr/bin/env bash
# =============================================================================
# Script     : update-dns.sh
# Phase      : 1 – Script 2 of 2
# Run From   : LOCAL WORKSTATION (after provision-infra.sh completes)
# Purpose    : Dynamically fetch all instance IPs and upsert Route 53 A records.
#              Also authorises the Frontend server's private IP for SSH on the
#              common SSH security group (making it the master orchestrator).
# =============================================================================
set -euo pipefail

# ─── COLOUR LOGGING ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[INFO ]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK   ]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}  $*" >&2; }

# ─── CONSTANTS ───────────────────────────────────────────────────────────────
HOSTED_ZONE_ID="Z094544866GQBYAJBQ7J"
HOSTED_ZONE_NAME="sagar90s.online"
TTL=1

# Static Instance ID for dispatch (no DNS, but we log its private IP)
DISPATCH_STATIC_INSTANCE_ID="i-09cc18ef27c7d5216"

# State file written by provision-infra.sh
STATE_FILE="/tmp/roboshop_provision_state.env"

# ─── DNS OUTPUT STATE ────────────────────────────────────────────────────────
DNS_STATE_FILE="/tmp/roboshop_dns_state.env"
touch "${DNS_STATE_FILE}"

# ─── LOAD PROVISION STATE ────────────────────────────────────────────────────
if [[ ! -f "${STATE_FILE}" ]]; then
  log_error "State file not found: ${STATE_FILE}"
  log_error "Please run provision-infra.sh first."
  exit 1
fi
source "${STATE_FILE}"
log_success "Loaded provision state from ${STATE_FILE}"

# ─── PREREQS ─────────────────────────────────────────────────────────────────
command -v aws >/dev/null 2>&1 || { log_error "aws CLI not found."; exit 1; }
command -v jq  >/dev/null 2>&1 || { log_error "jq not found.";      exit 1; }
aws sts get-caller-identity >/dev/null 2>&1 || { log_error "AWS credentials not configured."; exit 1; }

# ─── HELPER: Fetch IP for a given instance ID ────────────────────────────────
# Usage: get_ip <instance-id> <public|private>
get_ip() {
  local instance_id="$1" ip_type="$2"
  local query

  if [[ "${ip_type}" == "public" ]]; then
    query="Reservations[0].Instances[0].PublicIpAddress"
  else
    query="Reservations[0].Instances[0].PrivateIpAddress"
  fi

  local ip
  ip=$(aws ec2 describe-instances \
    --instance-ids "${instance_id}" \
    --query "${query}" --output text)

  if [[ -z "${ip}" || "${ip}" == "None" ]]; then
    log_error "Could not retrieve ${ip_type} IP for instance ${instance_id}"
    return 1
  fi
  echo "${ip}"
}

# ─── HELPER: Upsert a Route53 A record ───────────────────────────────────────
upsert_dns() {
  local fqdn="$1" ip="$2"

  log_info "Upserting DNS: ${fqdn} → ${ip} (TTL=${TTL})"

  local change_batch
  change_batch=$(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${fqdn}",
        "Type": "A",
        "TTL": ${TTL},
        "ResourceRecords": [
          { "Value": "${ip}" }
        ]
      }
    }
  ]
}
EOF
)

  local change_id
  change_id=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --change-batch "${change_batch}" \
    --query "ChangeInfo.Id" --output text)

  log_success "  DNS change submitted: ${change_id} → ${fqdn} = ${ip}"
}

# ─── DNS MAPPING TABLE ───────────────────────────────────────────────────────
# Format: "service_name:dns_name:ip_type"
# ip_type = public | private | none (no DNS, just log)
DNS_MAP=(
  "frontend:${HOSTED_ZONE_NAME}:public"
  "catalogue:catalog.${HOSTED_ZONE_NAME}:private"
  "user:user.${HOSTED_ZONE_NAME}:private"
  "cart:cart.${HOSTED_ZONE_NAME}:private"
  "shipping:shipping.${HOSTED_ZONE_NAME}:private"
  "payment:payment.${HOSTED_ZONE_NAME}:private"
  "mongodb:mongodb.${HOSTED_ZONE_NAME}:private"
  "redis:redis.${HOSTED_ZONE_NAME}:private"
  "mysql:mysql.${HOSTED_ZONE_NAME}:private"
  "rabbitmq:rabbitmq.${HOSTED_ZONE_NAME}:private"
  "dispatch:none:none"
)

# =============================================================================
# MAIN: Iterate and upsert DNS records
# =============================================================================
log_info "════════ Route 53 DNS Sync Engine ════════"

declare -A RESOLVED_IPS

for entry in "${DNS_MAP[@]}"; do
  SVC_NAME="${entry%%:*}"
  REST="${entry#*:}"
  DNS_NAME="${REST%%:*}"
  IP_TYPE="${REST##*:}"

  # Resolve instance ID from state
  STATE_KEY="INSTANCE_${SVC_NAME^^}_ID"
  INSTANCE_ID="${!STATE_KEY:-}"

  if [[ "${SVC_NAME}" == "dispatch" ]]; then
    # dispatch uses a static instance ID, no DNS record
    log_info "dispatch → using static instance ID: ${DISPATCH_STATIC_INSTANCE_ID}"
    DISPATCH_PRIVATE_IP=$(get_ip "${DISPATCH_STATIC_INSTANCE_ID}" "private")
    log_success "dispatch private IP resolved: ${DISPATCH_PRIVATE_IP}"
    RESOLVED_IPS["dispatch"]="${DISPATCH_PRIVATE_IP}"
    echo "DISPATCH_PRIVATE_IP=${DISPATCH_PRIVATE_IP}" >> "${DNS_STATE_FILE}"
    continue
  fi

  if [[ -z "${INSTANCE_ID}" ]]; then
    log_error "No instance ID found in state for service: ${SVC_NAME}"
    log_error "Re-run provision-infra.sh to ensure all instances are created."
    exit 1
  fi

  # Fetch IP
  IP=$(get_ip "${INSTANCE_ID}" "${IP_TYPE}")

  # Validate IP format (basic sanity check)
  if ! [[ "${IP}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid IP '${IP}' for ${SVC_NAME} (${IP_TYPE}). Aborting."
    exit 1
  fi

  RESOLVED_IPS["${SVC_NAME}"]="${IP}"

  # Upsert DNS
  upsert_dns "${DNS_NAME}" "${IP}"

  # Save to DNS state file
  echo "${SVC_NAME^^}_IP=${IP}" >> "${DNS_STATE_FILE}"
  echo "${SVC_NAME^^}_DNS=${DNS_NAME}" >> "${DNS_STATE_FILE}"
done

# =============================================================================
# POST-DNS: Authorise Frontend Private IP for SSH (master orchestrator)
# =============================================================================
log_info "════════ Authorising Frontend Private IP for SSH ════════"

FRONTEND_PRIVATE_IP=$(get_ip "${INSTANCE_FRONTEND_ID}" "private")
log_info "Frontend private IP: ${FRONTEND_PRIVATE_IP}"

# Authorise idempotently
aws ec2 authorize-security-group-ingress \
  --group-id "${SG_SSH_ID}" \
  --protocol tcp \
  --port 22 \
  --cidr "${FRONTEND_PRIVATE_IP}/32" 2>/dev/null \
  && log_success "Authorised SSH from frontend private IP ${FRONTEND_PRIVATE_IP}/32 on ${SG_SSH_ID}" \
  || log_warn "SSH rule for ${FRONTEND_PRIVATE_IP}/32 may already exist – skipping."

echo "FRONTEND_PRIVATE_IP=${FRONTEND_PRIVATE_IP}" >> "${DNS_STATE_FILE}"

# =============================================================================
# SUMMARY
# =============================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  DNS SYNC COMPLETE – RESOLUTION SUMMARY${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
printf "%-15s %-45s %-18s\n" "SERVICE" "DNS RECORD" "IP"
printf "%-15s %-45s %-18s\n" "-------" "----------" "--"
for entry in "${DNS_MAP[@]}"; do
  SVC_NAME="${entry%%:*}"
  REST="${entry#*:}"
  DNS_NAME="${REST%%:*}"
  IP="${RESOLVED_IPS[${SVC_NAME}]:-N/A}"
  printf "%-15s %-45s %-18s\n" "${SVC_NAME}" "${DNS_NAME}" "${IP}"
done
echo ""
log_success "DNS state saved to: ${DNS_STATE_FILE}"
log_info  "Frontend public IP for browser: ${RESOLVED_IPS[frontend]}"
log_info  "SSH to frontend: ssh ec2-user@${RESOLVED_IPS[frontend]}"
log_info  "Next step → SSH to frontend and run: bash deploy-all.sh"
