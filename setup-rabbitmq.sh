#!/bin/bash
# =============================================================================
# Roboshop - RabbitMQ Setup Script
# Runs ON: rabbitmq server
# Tech  : RabbitMQ 3.x + Erlang
# =============================================================================
set -euo pipefail

log()  { echo -e "\n\033[1;34m[rabbitmq]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[rabbitmq][OK]\033[0m $*"; }

# ── 1. Setup RabbitMQ + Erlang repos ─────────────────────────────────────────
log "Configuring RabbitMQ and Erlang repositories..."
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
ok "Repos configured."

# ── 2. Install RabbitMQ ───────────────────────────────────────────────────────
log "Installing rabbitmq-server..."
dnf install rabbitmq-server -y
ok "RabbitMQ installed."

# ── 3. Enable and start service ───────────────────────────────────────────────
log "Enabling and starting rabbitmq-server..."
systemctl enable rabbitmq-server
systemctl start rabbitmq-server
ok "RabbitMQ is running."

# ── 4. Create application user (idempotent) ───────────────────────────────────
log "Creating roboshop RabbitMQ user (idempotent)..."
if rabbitmqctl list_users | grep -q "^roboshop"; then
    ok "User 'roboshop' already exists — skipping creation."
else
    rabbitmqctl add_user roboshop roboshop123
    ok "User 'roboshop' created."
fi
rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"
ok "Permissions set for roboshop user."
