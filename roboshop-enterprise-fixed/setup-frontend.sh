#!/bin/bash
dnf module disable nginx -y
dnf install nginx unzip -y
systemctl enable nginx --now

rm -rf /usr/share/nginx/html/*

curl -L -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip

cd /usr/share/nginx/html

unzip -o /tmp/frontend.zip

cat >/etc/nginx/default.d/roboshop.conf <<EOF
proxy_http_version 1.1;

location /api/catalogue/ {
  proxy_pass http://catalog.sagar90s.online:8080/;
}

location /api/user/ {
  proxy_pass http://user.sagar90s.online:8080/;
}

location /api/cart/ {
  proxy_pass http://cart.sagar90s.online:8080/;
}

location /api/shipping/ {
  proxy_pass http://shipping.sagar90s.online:8080/;
}

location /api/payment/ {
  proxy_pass http://payment.sagar90s.online:8080/;
}
EOF

nginx -t
systemctl restart nginx
