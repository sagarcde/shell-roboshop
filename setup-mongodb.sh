#!/bin/bash
# =============================================================================
# Roboshop - MongoDB Setup Script
# Runs ON: mongodb server
# Tech  : MongoDB 7.x
# =============================================================================
set -euo pipefail

log()  { echo -e "\n\033[1;34m[mongodb]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[mongodb][OK]\033[0m $*"; }
err()  { echo -e "\033[1;31m[mongodb][ERROR]\033[0m $*" >&2; exit 1; }

# ── 1. Setup MongoDB 7.x repo ────────────────────────────────────────────────
log "Configuring MongoDB 7.x repository..."
cat > /etc/yum.repos.d/mongo.repo <<'EOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
enabled=1
gpgcheck=0
EOF
ok "Repo configured."

# ── 2. Install MongoDB ────────────────────────────────────────────────────────
log "Installing mongodb-org..."
dnf install mongodb-org -y
ok "MongoDB installed."

# ── 3. Bind to all interfaces (0.0.0.0) so remote services can connect ───────
log "Updating bind IP from 127.0.0.1 to 0.0.0.0..."
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mongod.conf
ok "Bind IP updated."

# ── 4. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting mongod..."
systemctl enable mongod
systemctl restart mongod
ok "mongod is running."
