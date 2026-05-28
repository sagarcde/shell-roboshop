#!/bin/bash
source /tmp/common.sh

dnf module disable nodejs -y
dnf module enable nodejs:20 -y

dnf install -y nodejs unzip

id roboshop || useradd roboshop

mkdir -p /app

curl -L -o /tmp/catalogue.zip https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip

cd /app
rm -rf /app/*
unzip -o /tmp/catalogue.zip

npm install

cat >/etc/systemd/system/catalogue.service <<EOF
[Unit]
Description=Catalogue Service

[Service]
User=roboshop
Environment=MONGO=true
Environment=MONGO_URL="mongodb://mongodb.sagar90s.online:27017/catalogue"
ExecStart=/bin/node /app/server.js
SyslogIdentifier=catalogue

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable catalogue --now

mongosh --host mongodb.sagar90s.online </app/db/master-data.js || true

validate $? "CATALOGUE INSTALL"
