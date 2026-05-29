#!/usr/bin/env bash
# =============================================================================
# Component  : Catalogue (Node.js 20 / MongoDB client)
# Run From   : deploy-all.sh via sshpass (on catalogue server)
# Env Vars   : MONGODB_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[catalogue]${NC} $*"; }
log_success() { echo -e "${GREEN}[catalogue]${NC} $*"; }
log_error()   { echo -e "${RED}[catalogue]${NC} $*" >&2; }

# MONGODB_HOST must be exported by the caller (deploy-all.sh)
MONGODB_HOST="${MONGODB_HOST:-mongodb.sagar90s.online}"

log_info "Starting Catalogue setup (MONGODB_HOST=${MONGODB_HOST}) ..."

# ─── 1. Node.js 20 ────────────────────────────────────────────────────────────
log_info "Enabling Node.js module v20 ..."
dnf module disable nodejs -y
dnf module enable  nodejs:20 -y
dnf install -y nodejs
node --version
log_success "Node.js $(node --version) installed."

# ─── 2. Application user (idempotent) ────────────────────────────────────────
if id roboshop &>/dev/null; then
  log_info "User 'roboshop' already exists – skipping."
else
  useradd --system --home /app --shell /sbin/nologin \
          --comment "roboshop system user" roboshop
  log_success "User 'roboshop' created."
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
log_info "Downloading catalogue application code ..."
curl -sL -o /tmp/catalogue.zip \
  https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip
cd /app
unzip -o /tmp/catalogue.zip
log_success "Application code extracted to /app"

# ─── 4. npm install ───────────────────────────────────────────────────────────
log_info "Installing npm dependencies ..."
cd /app
npm install
log_success "npm install complete."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
log_info "Writing /etc/systemd/system/catalogue.service ..."
cat > /etc/systemd/system/catalogue.service <<EOF
[Unit]
Description=Catalogue Service

[Service]
User=roboshop
Environment=MONGO=true
Environment=MONGO_URL="mongodb://${MONGODB_HOST}:27017/catalogue"
ExecStart=/bin/node /app/server.js
SyslogIdentifier=catalogue
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "catalogue.service unit written."

# ─── 6. Start service ─────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now catalogue
log_success "catalogue service enabled and started."

# ─── 7. MongoDB client + load master data ────────────────────────────────────
log_info "Installing MongoDB repo for mongosh client ..."
cat > /etc/yum.repos.d/mongo.repo <<'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
enabled=1
gpgcheck=0
EOF
dnf install -y mongodb-mongosh
log_success "mongosh client installed."

log_info "Loading catalogue master data into MongoDB at ${MONGODB_HOST} ..."
if mongosh --host "${MONGODB_HOST}" --eval "db.getSiblingDB('catalogue').products.countDocuments()" \
   | grep -q "^0$" 2>/dev/null || true; then
  mongosh --host "${MONGODB_HOST}" < /app/db/master-data.js
  log_success "Catalogue master data loaded."
else
  log_info "Master data may already be loaded – attempting anyway ..."
  mongosh --host "${MONGODB_HOST}" < /app/db/master-data.js || log_info "Load returned non-zero (possibly already seeded)."
fi

# ─── 8. Verify service ────────────────────────────────────────────────────────
sleep 3
systemctl is-active --quiet catalogue && log_success "catalogue is RUNNING." \
  || { log_error "catalogue service failed!"; journalctl -u catalogue -n 30 --no-pager; exit 1; }

log_success "Catalogue setup COMPLETE."
