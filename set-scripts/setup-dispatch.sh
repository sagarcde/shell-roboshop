#!/usr/bin/env bash
# =============================================================================
# Component  : Dispatch (Go Lang binary / RabbitMQ consumer)
# Run From   : deploy-all.sh via sshpass (on dispatch server)
# Env Vars   : RABBITMQ_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[dispatch]${NC} $*"; }
log_success() { echo -e "${GREEN}[dispatch]${NC} $*"; }
log_error()   { echo -e "${RED}[dispatch]${NC} $*" >&2; }

RABBITMQ_HOST="${RABBITMQ_HOST:-rabbitmq.sagar90s.online}"
AMQP_USER="roboshop"
AMQP_PASS="roboshop123"

log_info "Starting Dispatch setup (RABBITMQ=${RABBITMQ_HOST}) ..."

# ─── 1. Go Lang ───────────────────────────────────────────────────────────────
log_info "Installing golang ..."
dnf install -y golang
go version
log_success "Go installed."

# ─── 2. Application user ──────────────────────────────────────────────────────
if id roboshop &>/dev/null; then
  log_info "User 'roboshop' already exists – skipping."
else
  useradd --system --home /app --shell /sbin/nologin \
          --comment "roboshop system user" roboshop
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
log_info "Downloading dispatch application code ..."
curl -sL -o /tmp/dispatch.zip \
  https://roboshop-artifacts.s3.amazonaws.com/dispatch-v3.zip
cd /app && unzip -o /tmp/dispatch.zip
log_success "Application code extracted."

# ─── 4. Build Go binary ───────────────────────────────────────────────────────
log_info "Building dispatch Go binary ..."
cd /app
go mod init dispatch
go get
go build
log_success "dispatch binary built."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
cat > /etc/systemd/system/dispatch.service <<EOF
[Unit]
Description=Dispatch Service

[Service]
User=roboshop
Environment=AMQP_HOST=${RABBITMQ_HOST}
Environment=AMQP_USER=${AMQP_USER}
Environment=AMQP_PASS=${AMQP_PASS}
ExecStart=/app/dispatch
SyslogIdentifier=dispatch
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "dispatch.service unit written."

# ─── 6. Start service ─────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now dispatch
sleep 3
systemctl is-active --quiet dispatch && log_success "dispatch is RUNNING." \
  || { log_error "dispatch service failed!"; journalctl -u dispatch -n 30 --no-pager; exit 1; }

log_success "Dispatch setup COMPLETE. (Outbound AMQP consumer – no inbound port required)"
