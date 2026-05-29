#!/usr/bin/env bash
# =============================================================================
# Component  : RabbitMQ 3.x (with modern Erlang)
# Run From   : deploy-all.sh via sshpass (on rabbitmq server)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[rabbitmq]${NC} $*"; }
log_success() { echo -e "${GREEN}[rabbitmq]${NC} $*"; }
log_error()   { echo -e "${RED}[rabbitmq]${NC} $*" >&2; }

ROBOSHOP_AMQP_USER="roboshop"
ROBOSHOP_AMQP_PASS="roboshop123"

log_info "Starting RabbitMQ setup ..."

# ─── 1. Repo file (Erlang + RabbitMQ) ────────────────────────────────────────
log_info "Writing /etc/yum.repos.d/rabbitmq.repo ..."
cat > /etc/yum.repos.d/rabbitmq.repo <<'EOF'
[modern-erlang]
name=modern-erlang-el9
baseurl=https://yum1.novemberain.com/erlang/el/9/$basearch
        https://yum2.novemberain.com/erlang/el/9/$basearch
        https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-erlang/rpm/el/9/$basearch
enabled=1
gpgcheck=0

[modern-erlang-noarch]
name=modern-erlang-el9-noarch
baseurl=https://yum1.novemberain.com/erlang/el/9/noarch
        https://yum2.novemberain.com/erlang/el/9/noarch
        https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-erlang/rpm/el/9/noarch
enabled=1
gpgcheck=0

[modern-erlang-source]
name=modern-erlang-el9-source
baseurl=https://yum1.novemberain.com/erlang/el/9/SRPMS
        https://yum2.novemberain.com/erlang/el/9/SRPMS
        https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-erlang/rpm/el/9/SRPMS
enabled=1
gpgcheck=0

[rabbitmq-el9]
name=rabbitmq-el9
baseurl=https://yum2.novemberain.com/rabbitmq/el/9/$basearch
        https://yum1.novemberain.com/rabbitmq/el/9/$basearch
        https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-server/rpm/el/9/$basearch
enabled=1
gpgcheck=0

[rabbitmq-el9-noarch]
name=rabbitmq-el9-noarch
baseurl=https://yum2.novemberain.com/rabbitmq/el/9/noarch
        https://yum1.novemberain.com/rabbitmq/el/9/noarch
        https://dl.cloudsmith.io/public/rabbitmq/rabbitmq-server/rpm/el/9/noarch
enabled=1
gpgcheck=0
EOF
log_success "RabbitMQ repo file written."

# ─── 2. Install ───────────────────────────────────────────────────────────────
log_info "Installing rabbitmq-server ..."
dnf install -y rabbitmq-server
log_success "rabbitmq-server installed."

# ─── 3. Enable & Start ────────────────────────────────────────────────────────
log_info "Enabling and starting rabbitmq-server ..."
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
log_success "rabbitmq-server started."

# ─── 4. Create application user (idempotent) ─────────────────────────────────
log_info "Creating RabbitMQ application user '${ROBOSHOP_AMQP_USER}' ..."

if rabbitmqctl list_users 2>/dev/null | grep -q "^${ROBOSHOP_AMQP_USER}"; then
  log_info "User '${ROBOSHOP_AMQP_USER}' already exists – skipping creation."
else
  rabbitmqctl add_user "${ROBOSHOP_AMQP_USER}" "${ROBOSHOP_AMQP_PASS}"
  log_success "User '${ROBOSHOP_AMQP_USER}' created."
fi

log_info "Setting permissions for '${ROBOSHOP_AMQP_USER}' on vhost '/' ..."
rabbitmqctl set_permissions -p / "${ROBOSHOP_AMQP_USER}" ".*" ".*" ".*"
log_success "Permissions set."

# ─── 5. Verify ────────────────────────────────────────────────────────────────
sleep 2
systemctl is-active --quiet rabbitmq-server && log_success "rabbitmq-server is RUNNING." \
  || { log_error "rabbitmq-server failed!"; systemctl status rabbitmq-server --no-pager; exit 1; }

log_success "RabbitMQ setup COMPLETE. AMQP user: ${ROBOSHOP_AMQP_USER} / ${ROBOSHOP_AMQP_PASS}"
