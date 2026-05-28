#!/bin/bash
# =============================================================================
# Roboshop - User Service Setup Script
# Runs ON: user server
# Tech  : NodeJS 20, connects to MongoDB + Redis
# =============================================================================
set -euo pipefail

MONGODB_HOST="mongodb.sagar90s.online"
REDIS_HOST="redis.sagar90s.online"

log()  { echo -e "\n\033[1;34m[user]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[user][OK]\033[0m $*"; }

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
log "Downloading user application..."
mkdir -p /app
curl -sL -o /tmp/user.zip \
    https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip
cd /app && unzip -o /tmp/user.zip
ok "Application extracted to /app."

# ── 4. Install npm dependencies ───────────────────────────────────────────────
log "Installing npm dependencies..."
cd /app && npm install
ok "Dependencies installed."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/user.service..."
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

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting user service..."
systemctl daemon-reload
systemctl enable user
systemctl restart user
ok "User service is running."
