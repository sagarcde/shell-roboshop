#!/bin/bash
source ./common.sh

dnf install -y nginx unzip

systemctl enable nginx --now

rm -rf /usr/share/nginx/html/*

curl -L -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip

cd /usr/share/nginx/html

unzip -o /tmp/frontend.zip

systemctl restart nginx

validate $? "FRONTEND INSTALL"
