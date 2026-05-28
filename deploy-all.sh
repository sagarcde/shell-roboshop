#!/bin/bash
# =============================================================================
# Roboshop - Master Orchestrator Script
# Runs ON : frontend server
# Purpose : Push and execute all component setup scripts remotely via sshpass
#
# Deployment Order (dependency-first):
#   1.  mongodb     (no deps)
#   2.  redis       (no deps)
#   3.  mysql       (no deps)
#   4.  rabbitmq    (no deps)
#   5.  catalogue   (needs mongodb)
#   6.  user        (needs mongodb, redis)
#   7.  cart        (needs redis, catalogue)
#   8.  shipping    (needs mysql, cart)
#   9.  payment     (needs cart, user, rabbitmq)
#   10. dispatch    (needs rabbitmq) — uses AWS CLI for IP, no DNS record
#   11. frontend    (needs all above) — runs LOCALLY last
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# SECTION 1: CONFIGURATION
# =============================================================================

REMOTE_USER="ec2-user"
REMOTE_PASS="DevOps321"
REMOTE_SCRIPT_DIR="/tmp/roboshop-scripts"
DISPATCH_INSTANCE_ID="i-09cc18ef27c7d5216"    # No DNS — resolved via AWS CLI
LOG_DIR="/var/log/roboshop-deploy"
LOG_FILE="${LOG_DIR}/deploy-$(date +%Y%m%d-%H%M%S).log"

# =============================================================================
# SECTION 2: COMPONENT → HOST MAP
# Format: "COMPONENT|DNS_OR_IP|SCRIPT_FILE"
# dispatch uses IP resolved at runtime (see SECTION 5)
# =============================================================================

declare -a BACKEND_COMPONENTS=(
    "mongodb  | mongodb.sagar90s.online  | setup-mongodb.sh"
    "redis    | redis.sagar90s.online    | setup-redis.sh"
    "mysql    | mysql.sagar90s.online    | setup-mysql.sh"
    "rabbitmq | rabbitmq.sagar90s.online | setup-rabbitmq.sh"
    "catalogue| catalog.sagar90s.online  | setup-catalogue.sh"
    "user     | user.sagar90s.online     | setup-user.sh"
    "cart     | cart.sagar90s.online     | setup-cart.sh"
    "shipping | shipping.sagar90s.online | setup-shipping.sh"
    "payment  | payment.sagar90s.online  | setup-payment.sh"
)

# =============================================================================
# SECTION 3: HELPER FUNCTIONS
# =============================================================================

mkdir -p "$LOG_DIR"

log()     { local msg="[$(date '+%H:%M:%S')] [INFO]  $*"; echo -e "\n\033[1;34m${msg}\033[0m" | tee -a "$LOG_FILE"; }
ok()      { local msg="[$(date '+%H:%M:%S')] [OK]    $*"; echo -e "\033[1;32m${msg}\033[0m" | tee -a "$LOG_FILE"; }
warn()    { local msg="[$(date '+%H:%M:%S')] [WARN]  $*"; echo -e "\033[1;33m${msg}\033[0m" | tee -a "$LOG_FILE"; }
err()     { local msg="[$(date '+%H:%M:%S')] [ERROR] $*"; echo -e "\033[1;31m${msg}\033[0m" | tee -a "$LOG_FILE" >&2; }
divider() { echo "──────────────────────────────────────────────────────────" | tee -a "$LOG_FILE"; }

# SSH options shared across all remote calls
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=no"

# Push a script to a remote host and execute it as sudo
# Usage: remote_deploy "component" "host" "script.sh"
remote_deploy() {
    local component="$1"
    local host="$2"
    local script="$3"
    local script_path="$(dirname "$0")/${script}"

    divider
    log "▶ Deploying: ${component} → ${host}"

    # Validate script exists locally
    if [[ ! -f "$script_path" ]]; then
        err "${component}: Script not found at ${script_path}"
        return 1
    fi

    # Push the script via SCP
    log "${component}: Copying ${script} to ${host}:${REMOTE_SCRIPT_DIR}/"
    sshpass -p "${REMOTE_PASS}" scp ${SSH_OPTS} \
        "$script_path" \
        "${REMOTE_USER}@${host}:${REMOTE_SCRIPT_DIR}/${script}" 2>>"$LOG_FILE"

    # Execute the script remotely as sudo
    log "${component}: Executing script on ${host}..."
    sshpass -p "${REMOTE_PASS}" ssh ${SSH_OPTS} \
        "${REMOTE_USER}@${host}" \
        "sudo bash ${REMOTE_SCRIPT_DIR}/${script}" 2>>"$LOG_FILE"

    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        ok "${component}: Setup completed successfully on ${host}."
    else
        err "${component}: Setup FAILED on ${host} with exit code ${exit_code}."
        return $exit_code
    fi
}

# =============================================================================
# SECTION 4: PRE-FLIGHT CHECKS
# =============================================================================

log "=========================================="
log "  Roboshop Centralized Deployment Start"
log "  Log file: ${LOG_FILE}"
log "=========================================="

# Ensure sshpass is installed
if ! command -v sshpass &>/dev/null; then
    log "sshpass not found — installing..."
    dnf install sshpass -y
    ok "sshpass installed."
fi

# Ensure AWS CLI is available (needed for dispatch)
if ! command -v aws &>/dev/null; then
    err "AWS CLI is not installed. Required to resolve dispatch IP. Aborting."
    exit 1
fi

# Verify AWS credentials are configured
aws sts get-caller-identity &>/dev/null || {
    err "AWS credentials not configured. Run 'aws configure'. Aborting."
    exit 1
}
ok "AWS CLI authenticated."

# Ensure all local setup scripts exist
SCRIPT_DIR="$(dirname "$0")"
REQUIRED_SCRIPTS=(
    setup-mongodb.sh setup-redis.sh setup-mysql.sh setup-rabbitmq.sh
    setup-catalogue.sh setup-user.sh setup-cart.sh setup-shipping.sh
    setup-payment.sh setup-dispatch.sh setup-frontend.sh
)
MISSING=0
for s in "${REQUIRED_SCRIPTS[@]}"; do
    [[ ! -f "${SCRIPT_DIR}/${s}" ]] && { err "Missing script: ${s}"; MISSING=1; }
done
[[ $MISSING -eq 1 ]] && { err "One or more setup scripts are missing. Aborting."; exit 1; }
ok "All setup scripts present."

# Create remote script directory on each backend host (pre-flight)
ALL_HOSTS=(
    mongodb.sagar90s.online  redis.sagar90s.online
    mysql.sagar90s.online    rabbitmq.sagar90s.online
    catalog.sagar90s.online  user.sagar90s.online
    cart.sagar90s.online     shipping.sagar90s.online
    payment.sagar90s.online
)

log "Creating remote script directory on all backend nodes..."
for host in "${ALL_HOSTS[@]}"; do
    sshpass -p "${REMOTE_PASS}" ssh ${SSH_OPTS} \
        "${REMOTE_USER}@${host}" \
        "mkdir -p ${REMOTE_SCRIPT_DIR}" &>/dev/null \
        && ok "  ${host} — dir ready" \
        || warn "  ${host} — could not create dir (may retry during deploy)"
done

# =============================================================================
# SECTION 5: RESOLVE DISPATCH IP (No DNS record — use AWS CLI)
# =============================================================================

log "Resolving dispatch private IP from instance ID ${DISPATCH_INSTANCE_ID}..."
DISPATCH_IP=$(aws ec2 describe-instances \
    --instance-ids "${DISPATCH_INSTANCE_ID}" \
    --query "Reservations[0].Instances[0].PrivateIpAddress" \
    --output text)

if [[ -z "$DISPATCH_IP" || "$DISPATCH_IP" == "None" ]]; then
    err "Could not resolve private IP for dispatch (${DISPATCH_INSTANCE_ID}). Aborting."
    exit 1
fi
ok "Dispatch private IP resolved: ${DISPATCH_IP}"

# Pre-create script dir on dispatch server
sshpass -p "${REMOTE_PASS}" ssh ${SSH_OPTS} \
    "${REMOTE_USER}@${DISPATCH_IP}" \
    "mkdir -p ${REMOTE_SCRIPT_DIR}" &>/dev/null || true

# =============================================================================
# SECTION 6: DEPLOY BACKEND COMPONENTS
# =============================================================================

log "Starting backend deployments..."
FAILED_COMPONENTS=()

for entry in "${BACKEND_COMPONENTS[@]}"; do
    COMPONENT=$(echo "$entry" | awk -F'|' '{gsub(/ /,"",$1); print $1}')
    HOST=$(echo "$entry"      | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    SCRIPT=$(echo "$entry"    | awk -F'|' '{gsub(/ /,"",$3); print $3}')

    if remote_deploy "$COMPONENT" "$HOST" "$SCRIPT"; then
        ok "${COMPONENT} → SUCCESS"
    else
        err "${COMPONENT} → FAILED"
        FAILED_COMPONENTS+=("$COMPONENT")
        # Non-fatal: continue with remaining components.
        # Change to `exit 1` here if you want a strict halt-on-error mode.
    fi
done

# Deploy dispatch (using resolved IP instead of DNS)
divider
log "▶ Deploying: dispatch → ${DISPATCH_IP} (via IP — no DNS record)"

sshpass -p "${REMOTE_PASS}" scp ${SSH_OPTS} \
    "${SCRIPT_DIR}/setup-dispatch.sh" \
    "${REMOTE_USER}@${DISPATCH_IP}:${REMOTE_SCRIPT_DIR}/setup-dispatch.sh"

sshpass -p "${REMOTE_PASS}" ssh ${SSH_OPTS} \
    "${REMOTE_USER}@${DISPATCH_IP}" \
    "sudo bash ${REMOTE_SCRIPT_DIR}/setup-dispatch.sh" 2>>"$LOG_FILE"

if [[ $? -eq 0 ]]; then
    ok "dispatch → SUCCESS"
else
    err "dispatch → FAILED"
    FAILED_COMPONENTS+=("dispatch")
fi

# =============================================================================
# SECTION 7: DEPLOY FRONTEND (LOCAL — runs last)
# =============================================================================

divider
log "▶ Deploying: frontend → localhost (local execution)"

if bash "${SCRIPT_DIR}/setup-frontend.sh" 2>>"$LOG_FILE"; then
    ok "frontend → SUCCESS"
else
    err "frontend → FAILED"
    FAILED_COMPONENTS+=("frontend")
fi

# =============================================================================
# SECTION 8: FINAL SUMMARY
# =============================================================================

divider
echo ""
echo "════════════════════════════════════════════════════════════"
echo "         ROBOSHOP DEPLOYMENT — COMPLETE                    "
echo "════════════════════════════════════════════════════════════"

if [[ ${#FAILED_COMPONENTS[@]} -eq 0 ]]; then
    echo -e "\033[1;32m  ✅  All 11 components deployed successfully!\033[0m"
else
    echo -e "\033[1;31m  ❌  Failed components (${#FAILED_COMPONENTS[@]}):\033[0m"
    for c in "${FAILED_COMPONENTS[@]}"; do
        echo "       - $c"
    done
    echo ""
    echo "  Check log for details: ${LOG_FILE}"
fi

echo "════════════════════════════════════════════════════════════"
echo ""

[[ ${#FAILED_COMPONENTS[@]} -eq 0 ]] && exit 0 || exit 1
