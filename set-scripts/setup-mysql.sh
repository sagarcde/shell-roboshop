#!/usr/bin/env bash
# =============================================================================
# Component  : MySQL 8.x
# Run From   : deploy-all.sh via sshpass (on mysql server)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[mysql]${NC} $*"; }
log_success() { echo -e "${GREEN}[mysql]${NC} $*"; }
log_error()   { echo -e "${RED}[mysql]${NC} $*" >&2; }

MYSQL_ROOT_PASS="RoboShop@1"

log_info "Starting MySQL 8.x setup ..."

# ─── 1. Install ───────────────────────────────────────────────────────────────
log_info "Installing mysql-server ..."
dnf install -y mysql-server
log_success "mysql-server installed."

# ─── 2. Enable & Start ────────────────────────────────────────────────────────
log_info "Enabling and starting mysqld ..."
systemctl enable mysqld
systemctl start mysqld
log_success "mysqld service started."

# ─── 3. Secure installation / set root password (idempotent) ─────────────────
log_info "Running mysql_secure_installation (set root password) ..."

# Check if root password is already set by testing a connection
if mysql -uroot -p"${MYSQL_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1; then
  log_info "Root password is already set – skipping secure installation."
else
  mysql_secure_installation --set-root-pass "${MYSQL_ROOT_PASS}"
  log_success "MySQL root password set to: ${MYSQL_ROOT_PASS}"
fi

# ─── 4. Verify ────────────────────────────────────────────────────────────────
sleep 2
systemctl is-active --quiet mysqld && log_success "mysqld is RUNNING." \
  || { log_error "mysqld failed!"; systemctl status mysqld --no-pager; exit 1; }

log_success "MySQL setup COMPLETE. Root password: ${MYSQL_ROOT_PASS}"
