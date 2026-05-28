#!/bin/bash
dnf module disable nodejs -y
dnf module enable nodejs:20 -y
dnf install nodejs unzip -y
id roboshop || useradd roboshop
mkdir -p /app
curl -L -o /tmp/user.zip https://roboshop-artifacts.s3.amazonaws.com/user-v3.zip
cd /app
rm -rf /app/*
unzip -o /tmp/user.zip
npm install
