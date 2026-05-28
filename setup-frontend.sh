#!/bin/bash
# =============================================================================
# Roboshop - Frontend Setup Script
# Runs ON: frontend server (locally)
# Tech  : Nginx 1.24, static content + reverse proxy to all backends
# =============================================================================
set -euo pipefail

CATALOGUE_HOST="catalog.sagar90s.online"
USER_HOST="user.sagar90s.online"
CART_HOST="cart.sagar90s.online"
SHIPPING_HOST="shipping.sagar90s.online"
PAYMENT_HOST="payment.sagar90s.online"

log()  { echo -e "\n\033[1;34m[frontend]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[frontend][OK]\033[0m $*"; }

# ── 1. Install Nginx 1.24 ─────────────────────────────────────────────────────
log "Enabling Nginx 1.24 module..."
dnf module disable nginx -y
dnf module enable nginx:1.24 -y
dnf install nginx -y
ok "Nginx installed."

# ── 2. Enable and start Nginx ─────────────────────────────────────────────────
log "Starting Nginx..."
systemctl enable nginx
systemctl start nginx
ok "Nginx started."

# ── 3. Remove default content and deploy frontend ────────────────────────────
log "Deploying frontend static content..."
rm -rf /usr/share/nginx/html/*
curl -sL -o /tmp/frontend.zip \
    https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip
cd /usr/share/nginx/html && unzip -o /tmp/frontend.zip
ok "Frontend content deployed."

# ── 4. Write Nginx reverse-proxy config ──────────────────────────────────────
log "Writing Nginx reverse proxy config..."
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
ok "Nginx config written with all backend proxies."

# ── 5. Reload Nginx to apply config ──────────────────────────────────────────
log "Reloading Nginx..."
nginx -t && systemctl restart nginx
ok "Nginx restarted — Frontend is live!"
