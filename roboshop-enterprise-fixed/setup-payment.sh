#!/bin/bash
dnf install python3 gcc python3-devel unzip -y
id roboshop || useradd roboshop
mkdir -p /app
curl -L -o /tmp/payment.zip https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip
cd /app
rm -rf /app/*
unzip -o /tmp/payment.zip
pip3 install -r requirements.txt
