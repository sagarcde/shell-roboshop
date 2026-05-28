#!/bin/bash
source /tmp/common.sh

dnf module disable nodejs -y
dnf module enable nodejs:20 -y

dnf install -y nodejs unzip

id roboshop || useradd roboshop

mkdir -p /app

curl -L -o /tmp/cart.zip https://roboshop-artifacts.s3.amazonaws.com/cart-v3.zip

cd /app
rm -rf /app/*
unzip -o /tmp/cart.zip

npm install

validate $? "CART INSTALL"
