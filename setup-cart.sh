#!/usr/bin/env bash
# =============================================================================
# Component  : Cart (Node.js 20 / Redis + Catalogue)
# Run From   : deploy-all.sh via sshpass (on cart server)
# Env Vars   : REDIS_HOST, CATALOGUE_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[cart]${NC} $*"; }
log_success() { echo -e "${GREEN}[cart]${NC} $*"; }
log_error()   { echo -e "${RED}[cart]${NC} $*" >&2; }

REDIS_HOST="${REDIS_HOST:-redis.sagar90s.online}"
CATALOGUE_HOST="${CATALOGUE_HOST:-catalog.sagar90s.online}"

log_info "Starting Cart setup (REDIS=${REDIS_HOST}, CATALOGUE=${CATALOGUE_HOST}) ..."

# ─── 1. Node.js 20 ────────────────────────────────────────────────────────────
dnf module disable nodejs -y
dnf module enable  nodejs:20 -y
dnf install -y nodejs
log_success "Node.js $(node --version) installed."

# ─── 2. Application user ──────────────────────────────────────────────────────
if id roboshop &>/dev/null; then
  log_info "User 'roboshop' already exists – skipping."
else
  useradd --system --home /app --shell /sbin/nologin \
          --comment "roboshop system user" roboshop
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
curl -sL -o /tmp/cart.zip https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip
cd /app && unzip -o /tmp/cart.zip
log_success "Application code extracted."

# ─── 4. npm install ───────────────────────────────────────────────────────────
cd /app && npm install
log_success "npm install complete."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
cat > /etc/systemd/system/cart.service <<EOF
[Unit]
Description=Cart Service

[Service]
User=roboshop
Environment=REDIS_HOST=${REDIS_HOST}
Environment=CATALOGUE_HOST=${CATALOGUE_HOST}
Environment=CATALOGUE_PORT=8080
ExecStart=/bin/node /app/server.js
SyslogIdentifier=cart
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "cart.service unit written."

# ─── 6. Start service ─────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now cart
sleep 3
systemctl is-active --quiet cart && log_success "cart is RUNNING." \
  || { log_error "cart service failed!"; journalctl -u cart -n 30 --no-pager; exit 1; }

log_success "Cart setup COMPLETE."
