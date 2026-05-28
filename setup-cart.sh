#!/bin/bash
# =============================================================================
# Roboshop - Cart Service Setup Script
# Runs ON: cart server
# Tech  : NodeJS 20, connects to Redis + Catalogue
# =============================================================================
set -euo pipefail

REDIS_HOST="redis.sagar90s.online"
CATALOGUE_HOST="catalog.sagar90s.online"

log()  { echo -e "\n\033[1;34m[cart]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[cart][OK]\033[0m $*"; }

# ── 1. Install NodeJS 20 ──────────────────────────────────────────────────────
log "Enabling NodeJS 20 module..."
dnf module disable nodejs -y
dnf module enable nodejs:20 -y
dnf install nodejs -y
ok "NodeJS $(node -v) installed."

# ── 2. Create roboshop system user (idempotent) ───────────────────────────────
log "Creating roboshop system user..."
id roboshop &>/dev/null || useradd --system --home /app --shell /sbin/nologin \
    --comment "roboshop system user" roboshop
ok "User 'roboshop' ready."

# ── 3. Download and extract application ──────────────────────────────────────
log "Downloading cart application..."
mkdir -p /app
curl -sL -o /tmp/cart.zip \
    https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip
cd /app && unzip -o /tmp/cart.zip
ok "Application extracted to /app."

# ── 4. Install npm dependencies ───────────────────────────────────────────────
log "Installing npm dependencies..."
cd /app && npm install
ok "Dependencies installed."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/cart.service..."
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

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting cart service..."
systemctl daemon-reload
systemctl enable cart
systemctl restart cart
ok "Cart service is running."
