#!/usr/bin/env bash
# =============================================================================
# Script     : deploy-all.sh
# Phase      : 2 – Master Orchestrator
# Run From   : FRONTEND SERVER (roboshop-frontend EC2 instance)
# Purpose    : Centrally push and execute each component's setup script across
#              the cluster using sshpass. Maintains stateful progress tracking
#              for resumable execution on failure.
# =============================================================================
set -euo pipefail

# ─── COLOUR LOGGING ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[INFO ]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK   ]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN ]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}  $*" >&2; }
log_banner()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"; \
                echo -e "${BOLD}${CYAN}  $*${NC}"; \
                echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════${NC}"; }

# ─── CREDENTIALS ─────────────────────────────────────────────────────────────
REMOTE_USER="ec2-user"
REMOTE_PASS="DevOps321"

# ─── DNS ENDPOINTS (Route 53 internal DNS) ───────────────────────────────────
MONGODB_HOST="mongodb.sagar90s.online"
REDIS_HOST="redis.sagar90s.online"
CATALOGUE_HOST="catalog.sagar90s.online"
USER_HOST="user.sagar90s.online"
CART_HOST="cart.sagar90s.online"
SHIPPING_HOST="shipping.sagar90s.online"
PAYMENT_HOST="payment.sagar90s.online"
MYSQL_HOST="mysql.sagar90s.online"
RABBITMQ_HOST="rabbitmq.sagar90s.online"

# DISPATCH: no DNS – use private IP queried from AWS metadata or pre-set
# This should be set by reading /tmp/roboshop_dns_state.env if available,
# or override manually below.
DISPATCH_PRIVATE_IP="${DISPATCH_PRIVATE_IP:-}"

# ─── SCRIPT DIRECTORY ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPTS_DIR="${SCRIPT_DIR}/setup-scripts"

# ─── STATE FILE ──────────────────────────────────────────────────────────────
STATE_FILE="/var/tmp/roboshop_deploy_state.txt"
touch "${STATE_FILE}"

# ─── PREREQS ─────────────────────────────────────────────────────────────────
log_banner "Roboshop Centralized Deploy Orchestrator"

log_info "Checking prerequisites ..."
for cmd in sshpass ssh scp; do
  command -v "${cmd}" >/dev/null 2>&1 || {
    log_warn "${cmd} not found. Installing ..."
    sudo dnf install -y "${cmd}" 2>/dev/null || sudo yum install -y "${cmd}" 2>/dev/null || true
  }
done
command -v sshpass >/dev/null 2>&1 || { log_error "sshpass could not be installed. Aborting."; exit 1; }
log_success "Prerequisites OK"

# If DISPATCH_PRIVATE_IP is not set, try to read from DNS state file
if [[ -z "${DISPATCH_PRIVATE_IP}" ]]; then
  DNS_STATE="/tmp/roboshop_dns_state.env"
  if [[ -f "${DNS_STATE}" ]]; then
    source "${DNS_STATE}"
    DISPATCH_PRIVATE_IP="${DISPATCH_PRIVATE_IP:-}"
  fi
fi

if [[ -z "${DISPATCH_PRIVATE_IP}" ]]; then
  log_warn "DISPATCH_PRIVATE_IP is not set. Please set it manually:"
  log_warn "  export DISPATCH_PRIVATE_IP=172.31.12.105"
  log_warn "  Then re-run this script."
  exit 1
fi

log_info "Dispatch private IP: ${DISPATCH_PRIVATE_IP}"

# ─── HELPER: Check if a step already completed ───────────────────────────────
is_completed() {
  grep -qxF "COMPLETED:$1" "${STATE_FILE}" 2>/dev/null
}

mark_completed() {
  echo "COMPLETED:$1" >> "${STATE_FILE}"
  log_success "Step '${1}' marked as COMPLETED."
}

mark_failed() {
  echo "FAILED:$1" >> "${STATE_FILE}"
  log_error "Step '${1}' FAILED. Check logs above."
}

# ─── HELPER: Deploy a setup script to a remote host ──────────────────────────
# Usage: deploy_component <step_name> <remote_host> <setup_script_path> [extra_env_vars...]
# Extra env vars format: "KEY=VALUE"
deploy_component() {
  local step_name="$1"
  local remote_host="$2"
  local setup_script="$3"
  shift 3
  local extra_env_vars=("$@")

  if is_completed "${step_name}"; then
    log_warn "Step '${step_name}' already completed – skipping."
    return 0
  fi

  log_banner "Deploying: ${step_name} → ${remote_host}"

  if [[ ! -f "${setup_script}" ]]; then
    log_error "Setup script not found: ${setup_script}"
    mark_failed "${step_name}"
    exit 1
  fi

  local remote_script="/tmp/$(basename "${setup_script}")"

  # Copy script to remote host
  log_info "Pushing ${setup_script} → ${remote_host}:${remote_script} ..."
  sshpass -p "${REMOTE_PASS}" scp \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=30 \
    "${setup_script}" \
    "${REMOTE_USER}@${remote_host}:${remote_script}"

  # Build env var export string for remote execution
  local env_exports=""
  for kv in "${extra_env_vars[@]:-}"; do
    [[ -n "${kv}" ]] && env_exports+="export ${kv}; "
  done

  # Execute script on remote host via sudo
  log_info "Executing script on ${remote_host} ..."
  sshpass -p "${REMOTE_PASS}" ssh \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=30 \
    "${REMOTE_USER}@${remote_host}" \
    "chmod +x ${remote_script}; ${env_exports} echo '${REMOTE_PASS}' | sudo -S bash ${remote_script}"

  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    mark_failed "${step_name}"
    log_error "Remote execution FAILED for ${step_name} on ${remote_host} (exit code: ${exit_code})"
    exit 1
  fi

  mark_completed "${step_name}"
}

# =============================================================================
# DEPLOYMENT SEQUENCE
# NOTE: Order matters! Data stores must be ready before app services.
# =============================================================================

# 1. MongoDB
deploy_component "mongodb"   "${MONGODB_HOST}"   "${SETUP_SCRIPTS_DIR}/setup-mongodb.sh"

# 2. Redis
deploy_component "redis"     "${REDIS_HOST}"     "${SETUP_SCRIPTS_DIR}/setup-redis.sh"

# 3. MySQL
deploy_component "mysql"     "${MYSQL_HOST}"     "${SETUP_SCRIPTS_DIR}/setup-mysql.sh"

# 4. RabbitMQ
deploy_component "rabbitmq"  "${RABBITMQ_HOST}"  "${SETUP_SCRIPTS_DIR}/setup-rabbitmq.sh"

# 5. Catalogue (depends on MongoDB)
deploy_component "catalogue" "${CATALOGUE_HOST}" "${SETUP_SCRIPTS_DIR}/setup-catalogue.sh" \
  "MONGODB_HOST=${MONGODB_HOST}"

# 6. User (depends on MongoDB + Redis)
deploy_component "user"      "${USER_HOST}"      "${SETUP_SCRIPTS_DIR}/setup-user.sh" \
  "MONGODB_HOST=${MONGODB_HOST}" \
  "REDIS_HOST=${REDIS_HOST}"

# 7. Cart (depends on Redis + Catalogue)
deploy_component "cart"      "${CART_HOST}"      "${SETUP_SCRIPTS_DIR}/setup-cart.sh" \
  "REDIS_HOST=${REDIS_HOST}" \
  "CATALOGUE_HOST=${CATALOGUE_HOST}"

# 8. Shipping (depends on Cart + MySQL)
deploy_component "shipping"  "${SHIPPING_HOST}"  "${SETUP_SCRIPTS_DIR}/setup-shipping.sh" \
  "CART_HOST=${CART_HOST}" \
  "MYSQL_HOST=${MYSQL_HOST}"

# 9. Payment (depends on Cart + User + RabbitMQ)
deploy_component "payment"   "${PAYMENT_HOST}"   "${SETUP_SCRIPTS_DIR}/setup-payment.sh" \
  "CART_HOST=${CART_HOST}" \
  "USER_HOST=${USER_HOST}" \
  "RABBITMQ_HOST=${RABBITMQ_HOST}"

# 10. Dispatch (depends on RabbitMQ) – uses private IP, no DNS
deploy_component "dispatch"  "${DISPATCH_PRIVATE_IP}" "${SETUP_SCRIPTS_DIR}/setup-dispatch.sh" \
  "RABBITMQ_HOST=${RABBITMQ_HOST}"

# 11. Frontend – LAST (depends on all backend services being alive)
log_banner "Deploying: frontend (local execution)"
if is_completed "frontend"; then
  log_warn "Step 'frontend' already completed – skipping."
else
  bash "${SETUP_SCRIPTS_DIR}/setup-frontend.sh" \
    CATALOGUE_HOST="${CATALOGUE_HOST}" \
    USER_HOST="${USER_HOST}" \
    CART_HOST="${CART_HOST}" \
    SHIPPING_HOST="${SHIPPING_HOST}" \
    PAYMENT_HOST="${PAYMENT_HOST}" \
    && mark_completed "frontend" \
    || { mark_failed "frontend"; exit 1; }
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
log_banner "ALL DEPLOYMENTS COMPLETE"
echo ""
log_success "State log: ${STATE_FILE}"
echo ""
cat "${STATE_FILE}"
echo ""
log_info "Open your browser: http://sagar90s.online"
