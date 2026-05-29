#!/usr/bin/env bash
# =============================================================================
# Component  : MongoDB 7.x
# Run From   : deploy-all.sh via sshpass (on mongodb server)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[mongodb]${NC} $*"; }
log_success() { echo -e "${GREEN}[mongodb]${NC} $*"; }
log_error()   { echo -e "${RED}[mongodb]${NC} $*" >&2; }

log_info "Starting MongoDB 7.x setup ..."

# ─── 1. Repo file ─────────────────────────────────────────────────────────────
log_info "Configuring MongoDB 7.0 YUM repository ..."
cat > /etc/yum.repos.d/mongo.repo <<'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
enabled=1
gpgcheck=0
EOF
log_success "MongoDB repo file written."

# ─── 2. Install ───────────────────────────────────────────────────────────────
log_info "Installing mongodb-org ..."
dnf install -y mongodb-org
log_success "mongodb-org installed."

# ─── 3. Bind address: 127.0.0.1 → 0.0.0.0 ───────────────────────────────────
log_info "Updating bindIp to 0.0.0.0 in /etc/mongod.conf ..."
if grep -q "bindIp: 127.0.0.1" /etc/mongod.conf; then
  sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf
  log_success "bindIp updated."
else
  log_info "bindIp already set to 0.0.0.0 or uses different key – skipping sed."
fi

# ─── 4. Enable & start ────────────────────────────────────────────────────────
log_info "Enabling and starting mongod service ..."
systemctl enable mongod
systemctl restart mongod
log_success "mongod service is active."

# ─── 5. Verify ────────────────────────────────────────────────────────────────
sleep 3
systemctl is-active --quiet mongod && log_success "mongod is RUNNING." \
  || { log_error "mongod failed to start!"; systemctl status mongod --no-pager; exit 1; }

log_success "MongoDB setup COMPLETE."
