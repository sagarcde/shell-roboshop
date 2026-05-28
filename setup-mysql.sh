#!/bin/bash
# =============================================================================
# Roboshop - MySQL Setup Script
# Runs ON: mysql server
# Tech  : MySQL 8.x
# =============================================================================
set -euo pipefail

log()  { echo -e "\n\033[1;34m[mysql]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[mysql][OK]\033[0m $*"; }

# ── 1. Install MySQL Server ───────────────────────────────────────────────────
log "Installing mysql-server..."
dnf install mysql-server -y
ok "MySQL installed."

# ── 2. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting mysqld..."
systemctl enable mysqld
systemctl start mysqld
ok "MySQL is running."

# ── 3. Set root password (idempotent — skip if already set) ──────────────────
log "Setting root password (RoboShop@1)..."
# mysql_secure_installation --set-root-pass is non-interactive only on first run
if mysql -uroot -e "SELECT 1" &>/dev/null 2>&1; then
    mysql_secure_installation --set-root-pass RoboShop@1
    ok "Root password set."
else
    ok "Root password already set — skipping."
fi
