#!/bin/bash
source /tmp/common.sh

dnf install -y maven unzip

id roboshop || useradd roboshop

mkdir -p /app

curl -L -o /tmp/shipping.zip https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip

cd /app
rm -rf /app/*
unzip -o /tmp/shipping.zip

mvn clean package

validate $? "SHIPPING INSTALL"
