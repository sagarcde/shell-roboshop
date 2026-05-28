#!/bin/bash
# =============================================================================
# Roboshop - Payment Service Setup Script
# Runs ON: payment server
# Tech  : Python 3 / uWSGI, connects to Cart + User + RabbitMQ
# =============================================================================
set -euo pipefail

CART_HOST="cart.sagar90s.online"
USER_HOST="user.sagar90s.online"
RABBITMQ_HOST="rabbitmq.sagar90s.online"

log()  { echo -e "\n\033[1;34m[payment]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[payment][OK]\033[0m $*"; }

# ── 1. Install Python 3 and build tools ───────────────────────────────────────
log "Installing Python 3, gcc, python3-devel..."
dnf install python3 gcc python3-devel -y
ok "Python $(python3 --version) installed."

# ── 2. Create roboshop system user (idempotent) ───────────────────────────────
log "Creating roboshop system user..."
id roboshop &>/dev/null || useradd --system --home /app --shell /sbin/nologin \
    --comment "roboshop system user" roboshop
ok "User 'roboshop' ready."

# ── 3. Download and extract application ──────────────────────────────────────
log "Downloading payment application..."
mkdir -p /app
curl -sL -o /tmp/payment.zip \
    https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip
cd /app && unzip -o /tmp/payment.zip
ok "Application extracted to /app."

# ── 4. Install Python dependencies ───────────────────────────────────────────
log "Installing pip3 requirements..."
cd /app && pip3 install -r requirements.txt
ok "Python dependencies installed."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/payment.service..."
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
Environment=AMQP_USER=roboshop
Environment=AMQP_PASS=roboshop123
ExecStart=/usr/local/bin/uwsgi --ini payment.ini
ExecStop=/bin/kill -9 \$MAINPID
SyslogIdentifier=payment

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting payment service..."
systemctl daemon-reload
systemctl enable payment
systemctl restart payment
ok "Payment service is running."
