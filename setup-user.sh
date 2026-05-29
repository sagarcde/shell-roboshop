#!/usr/bin/env bash
# =============================================================================
# Component  : User (Node.js 20 / MongoDB + Redis)
# Run From   : deploy-all.sh via sshpass (on user server)
# Env Vars   : MONGODB_HOST, REDIS_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[user]${NC} $*"; }
log_success() { echo -e "${GREEN}[user]${NC} $*"; }
log_error()   { echo -e "${RED}[user]${NC} $*" >&2; }

MONGODB_HOST="${MONGODB_HOST:-mongodb.sagar90s.online}"
REDIS_HOST="${REDIS_HOST:-redis.sagar90s.online}"

log_info "Starting User setup (MONGODB=${MONGODB_HOST}, REDIS=${REDIS_HOST}) ..."

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
  log_success "User 'roboshop' created."
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
log_info "Downloading user application code ..."
curl -sL -o /tmp/user.zip \
  https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip
cd /app
unzip -o /tmp/user.zip
log_success "Application code extracted."

# ─── 4. npm install ───────────────────────────────────────────────────────────
cd /app && npm install
log_success "npm install complete."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
cat > /etc/systemd/system/user.service <<EOF
[Unit]
Description=User Service

[Service]
User=roboshop
Environment=MONGO=true
Environment=REDIS_URL='redis://${REDIS_HOST}:6379'
Environment=MONGO_URL="mongodb://${MONGODB_HOST}:27017/users"
ExecStart=/bin/node /app/server.js
SyslogIdentifier=user
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "user.service unit written."

# ─── 6. Start service ─────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now user
sleep 3
systemctl is-active --quiet user && log_success "user is RUNNING." \
  || { log_error "user service failed!"; journalctl -u user -n 30 --no-pager; exit 1; }

log_success "User setup COMPLETE."
