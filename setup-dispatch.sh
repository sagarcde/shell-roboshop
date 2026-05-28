#!/bin/bash
# =============================================================================
# Roboshop - Dispatch Service Setup Script
# Runs ON: dispatch server
# Tech  : GoLang, connects to RabbitMQ
# =============================================================================
set -euo pipefail

RABBITMQ_HOST="rabbitmq.sagar90s.online"

log()  { echo -e "\n\033[1;34m[dispatch]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[dispatch][OK]\033[0m $*"; }

# ── 1. Install GoLang ─────────────────────────────────────────────────────────
log "Installing golang..."
dnf install golang -y
ok "Go $(go version) installed."

# ── 2. Create roboshop system user (idempotent) ───────────────────────────────
log "Creating roboshop system user..."
id roboshop &>/dev/null || useradd --system --home /app --shell /sbin/nologin \
    --comment "roboshop system user" roboshop
ok "User 'roboshop' ready."

# ── 3. Download and extract application ──────────────────────────────────────
log "Downloading dispatch application..."
mkdir -p /app
curl -sL -o /tmp/dispatch.zip \
    https://roboshop-artifacts.s3.amazonaws.com/dispatch-v3.zip
cd /app && unzip -o /tmp/dispatch.zip
ok "Application extracted to /app."

# ── 4. Build the Go binary ────────────────────────────────────────────────────
log "Building dispatch binary..."
cd /app
go mod init dispatch
go get
go build
ok "Dispatch binary built."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/dispatch.service..."
cat > /etc/systemd/system/dispatch.service <<EOF
[Unit]
Description=Dispatch Service

[Service]
User=roboshop
Environment=AMQP_HOST=${RABBITMQ_HOST}
Environment=AMQP_USER=roboshop
Environment=AMQP_PASS=roboshop123
ExecStart=/app/dispatch
SyslogIdentifier=dispatch

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting dispatch service..."
systemctl daemon-reload
systemctl enable dispatch
systemctl restart dispatch
ok "Dispatch service is running."
