#!/bin/bash
# =============================================================================
# Roboshop - Redis Setup Script
# Runs ON: redis server
# Tech  : Redis 7.x
# =============================================================================
set -euo pipefail

log()  { echo -e "\n\033[1;34m[redis]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[redis][OK]\033[0m $*"; }

# ── 1. Enable Redis 7 module ──────────────────────────────────────────────────
log "Enabling Redis 7 module..."
dnf module disable redis -y
dnf module enable redis:7 -y
ok "Redis 7 module enabled."

# ── 2. Install Redis ──────────────────────────────────────────────────────────
log "Installing redis..."
dnf install redis -y
ok "Redis installed."

# ── 3. Bind to 0.0.0.0 and disable protected-mode for remote access ──────────
log "Configuring redis to listen on 0.0.0.0 with protected-mode off..."
sed -i 's/^bind 127.0.0.1/bind 0.0.0.0/' /etc/redis/redis.conf
sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis/redis.conf
ok "Redis config updated."

# ── 4. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting redis..."
systemctl enable redis
systemctl restart redis
ok "Redis is running."
