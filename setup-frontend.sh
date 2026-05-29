#!/usr/bin/env bash
# =============================================================================
# Component  : Frontend (Nginx 1.24 + Reverse Proxy)
# Run From   : deploy-all.sh LOCALLY on the frontend server (NOT via sshpass)
# Env Vars   : CATALOGUE_HOST, USER_HOST, CART_HOST, SHIPPING_HOST,
#              PAYMENT_HOST (injected by deploy-all.sh or exported in env)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()    { echo -e "${CYAN}[frontend]${NC} $*"; }
log_success() { echo -e "${GREEN}[frontend]${NC} $*"; }
log_error()   { echo -e "${RED}[frontend]${NC} $*" >&2; }

# When called from deploy-all.sh with "KEY=VALUE" positional args, parse them
for arg in "$@"; do
  case "${arg}" in
    *=*) export "${arg}" ;;
  esac
done

CATALOGUE_HOST="${CATALOGUE_HOST:-catalog.sagar90s.online}"
USER_HOST="${USER_HOST:-user.sagar90s.online}"
CART_HOST="${CART_HOST:-cart.sagar90s.online}"
SHIPPING_HOST="${SHIPPING_HOST:-shipping.sagar90s.online}"
PAYMENT_HOST="${PAYMENT_HOST:-payment.sagar90s.online}"

log_info "Starting Frontend setup ..."
log_info "  catalogue  → ${CATALOGUE_HOST}"
log_info "  user       → ${USER_HOST}"
log_info "  cart       → ${CART_HOST}"
log_info "  shipping   → ${SHIPPING_HOST}"
log_info "  payment    → ${PAYMENT_HOST}"

# ─── 1. Nginx 1.24 ───────────────────────────────────────────────────────────
log_info "Enabling Nginx module v1.24 ..."
dnf module disable nginx -y
dnf module enable  nginx:1.24 -y
dnf install -y nginx
nginx -v
log_success "Nginx installed."

# ─── 2. Enable & start (initial default page) ────────────────────────────────
systemctl enable nginx
systemctl start  nginx

# ─── 3. Remove default web content ───────────────────────────────────────────
log_info "Removing default Nginx web content ..."
rm -rf /usr/share/nginx/html/*
log_success "Default content removed."

# ─── 4. Download & extract frontend static content ───────────────────────────
log_info "Downloading Roboshop frontend assets ..."
curl -sL -o /tmp/frontend.zip \
  https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip
cd /usr/share/nginx/html
unzip -o /tmp/frontend.zip
log_success "Frontend assets extracted to /usr/share/nginx/html"

# ─── 5. Write nginx.conf with reverse proxy rules ────────────────────────────
log_info "Writing /etc/nginx/nginx.conf with reverse proxy configuration ..."
cat > /etc/nginx/nginx.conf <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log notice;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen       80;
        listen       [::]:80;
        server_name  _;
        root         /usr/share/nginx/html;

        include /etc/nginx/default.d/*.conf;

        error_page 404 /404.html;
        location = /404.html {}

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {}

        location /images/ {
          expires 5s;
          root   /usr/share/nginx/html;
          try_files \$uri /images/placeholder.jpg;
        }

        # Reverse proxy to backend microservices via internal DNS
        location /api/catalogue/ { proxy_pass http://${CATALOGUE_HOST}:8080/; }
        location /api/user/      { proxy_pass http://${USER_HOST}:8080/; }
        location /api/cart/      { proxy_pass http://${CART_HOST}:8080/; }
        location /api/shipping/  { proxy_pass http://${SHIPPING_HOST}:8080/; }
        location /api/payment/   { proxy_pass http://${PAYMENT_HOST}:8080/; }

        location /health {
          stub_status on;
          access_log off;
        }
    }
}
EOF
log_success "nginx.conf written with DNS-based reverse proxy entries."

# ─── 6. Validate nginx config & restart ──────────────────────────────────────
log_info "Validating nginx configuration ..."
nginx -t
log_success "nginx config is valid."

log_info "Restarting nginx ..."
systemctl restart nginx
sleep 2
systemctl is-active --quiet nginx && log_success "nginx is RUNNING." \
  || { log_error "nginx failed to start!"; journalctl -u nginx -n 30 --no-pager; exit 1; }

log_success "Frontend setup COMPLETE."
log_success "Roboshop is now accessible at http://sagar90s.online"
