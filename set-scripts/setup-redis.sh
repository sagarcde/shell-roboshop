#!/usr/bin/env bash
# =============================================================================
# Component  : Redis 7.x
# Run From   : deploy-all.sh via sshpass (on redis server)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[redis]${NC} $*"; }
log_success() { echo -e "${GREEN}[redis]${NC} $*"; }
log_error()   { echo -e "${RED}[redis]${NC} $*" >&2; }

log_info "Starting Redis 7.x setup ..."

# ─── 1. Enable Redis 7 module ─────────────────────────────────────────────────
log_info "Switching to Redis module version 7 ..."
dnf module disable redis -y
dnf module enable  redis:7 -y
log_success "Redis module version 7 enabled."

# ─── 2. Install ───────────────────────────────────────────────────────────────
log_info "Installing redis ..."
dnf install -y redis
log_success "Redis installed."

# ─── 3. Bind 0.0.0.0 and disable protected-mode ──────────────────────────────
log_info "Configuring /etc/redis/redis.conf ..."
REDIS_CONF="/etc/redis/redis.conf"

# Update bind address
if grep -q "^bind 127.0.0.1" "${REDIS_CONF}"; then
  sed -i 's/^bind 127.0.0.1.*/bind 0.0.0.0/' "${REDIS_CONF}"
  log_success "bind set to 0.0.0.0"
else
  log_info "bind line already updated or not present – skipping."
fi

# Disable protected mode
if grep -q "^protected-mode yes" "${REDIS_CONF}"; then
  sed -i 's/^protected-mode yes/protected-mode no/' "${REDIS_CONF}"
  log_success "protected-mode set to no"
else
  log_info "protected-mode already set to no or not present – skipping."
fi

# ─── 4. Enable & start ────────────────────────────────────────────────────────
log_info "Enabling and starting redis service ..."
systemctl enable redis
systemctl restart redis
log_success "redis service is active."

# ─── 5. Verify ────────────────────────────────────────────────────────────────
sleep 2
systemctl is-active --quiet redis && log_success "redis is RUNNING." \
  || { log_error "redis failed to start!"; systemctl status redis --no-pager; exit 1; }

log_success "Redis setup COMPLETE."
