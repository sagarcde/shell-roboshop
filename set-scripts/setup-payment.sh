#!/usr/bin/env bash
# =============================================================================
# Component  : Payment (Python 3 / uWSGI + Cart + User + RabbitMQ)
# Run From   : deploy-all.sh via sshpass (on payment server)
# Env Vars   : CART_HOST, USER_HOST, RABBITMQ_HOST (injected by deploy-all.sh)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[payment]${NC} $*"; }
log_success() { echo -e "${GREEN}[payment]${NC} $*"; }
log_error()   { echo -e "${RED}[payment]${NC} $*" >&2; }

CART_HOST="${CART_HOST:-cart.sagar90s.online}"
USER_HOST="${USER_HOST:-user.sagar90s.online}"
RABBITMQ_HOST="${RABBITMQ_HOST:-rabbitmq.sagar90s.online}"
AMQP_USER="roboshop"
AMQP_PASS="roboshop123"

log_info "Starting Payment setup (CART=${CART_HOST}, USER=${USER_HOST}, AMQP=${RABBITMQ_HOST}) ..."

# ─── 1. Python 3 + build deps ─────────────────────────────────────────────────
log_info "Installing Python 3, gcc, python3-devel ..."
dnf install -y python3 gcc python3-devel
python3 --version
log_success "Python 3 installed."

# ─── 2. Application user ──────────────────────────────────────────────────────
if id roboshop &>/dev/null; then
  log_info "User 'roboshop' already exists – skipping."
else
  useradd --system --home /app --shell /sbin/nologin \
          --comment "roboshop system user" roboshop
fi

# ─── 3. App directory & code ─────────────────────────────────────────────────
[[ -d /app ]] || mkdir -p /app
log_info "Downloading payment application code ..."
curl -sL -o /tmp/payment.zip \
  https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip
cd /app && unzip -o /tmp/payment.zip
log_success "Application code extracted."

# ─── 4. pip install requirements ─────────────────────────────────────────────
log_info "Installing Python requirements ..."
cd /app
pip3 install -r requirements.txt
log_success "pip3 install complete."

# ─── 5. SystemD service unit ─────────────────────────────────────────────────
cat > /etc/systemd/system/payment.service <<EOF
[Unit]
Description=Payment Service

[Service]
User=root
WorkingDirectory=/app
Environment=CART_HOST=${CART_HOST}
Environment=CART_PORT=8080
Environment=USER_HOST=${USER_HOST}
Environment=USER_PORT=8080
Environment=AMQP_HOST=${RABBITMQ_HOST}
Environment=AMQP_USER=${AMQP_USER}
Environment=AMQP_PASS=${AMQP_PASS}
ExecStart=/usr/local/bin/uwsgi --ini payment.ini
ExecStop=/bin/kill -9 \$MAINPID
SyslogIdentifier=payment
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
log_success "payment.service unit written."

# ─── 6. Start service ─────────────────────────────────────────────────────────
systemctl daemon-reload
systemctl enable --now payment
sleep 3
systemctl is-active --quiet payment && log_success "payment is RUNNING." \
  || { log_error "payment service failed!"; journalctl -u payment -n 30 --no-pager; exit 1; }

log_success "Payment setup COMPLETE."
