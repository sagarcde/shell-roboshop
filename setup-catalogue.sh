#!/bin/bash
# =============================================================================
# Roboshop - Catalogue Setup Script
# Runs ON: catalogue server
# Tech  : NodeJS 20, connects to MongoDB
# =============================================================================
set -euo pipefail

MONGODB_HOST="mongodb.sagar90s.online"

log()  { echo -e "\n\033[1;34m[catalogue]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[catalogue][OK]\033[0m $*"; }

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
log "Downloading catalogue application..."
mkdir -p /app
curl -sL -o /tmp/catalogue.zip \
    https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip
cd /app && unzip -o /tmp/catalogue.zip
ok "Application extracted to /app."

# ── 4. Install npm dependencies ───────────────────────────────────────────────
log "Installing npm dependencies..."
cd /app && npm install
ok "Dependencies installed."

# ── 5. Write systemd service ──────────────────────────────────────────────────
log "Writing /etc/systemd/system/catalogue.service..."
cat > /etc/systemd/system/catalogue.service <<EOF
[Unit]
Description=Catalogue Service

[Service]
User=roboshop
Environment=MONGO=true
Environment=MONGO_URL="mongodb://${MONGODB_HOST}:27017/catalogue"
ExecStart=/bin/node /app/server.js
SyslogIdentifier=catalogue

[Install]
WantedBy=multi-user.target
EOF
ok "Service file written."

# ── 6. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting catalogue..."
systemctl daemon-reload
systemctl enable catalogue
systemctl restart catalogue
ok "Catalogue service is running."

# ── 7. Load MongoDB master data (schema + products) ──────────────────────────
log "Setting up MongoDB repo to get mongosh client..."
cat > /etc/yum.repos.d/mongo.repo <<'REPOEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
enabled=1
gpgcheck=0
REPOEOF
dnf install mongodb-mongosh -y

log "Loading catalogue master data into MongoDB..."
mongosh --host "${MONGODB_HOST}" < /app/db/master-data.js
ok "Master data loaded into MongoDB."
