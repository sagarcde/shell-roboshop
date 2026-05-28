#!/bin/bash
source /tmp/common.sh

dnf install -y golang unzip

id roboshop || useradd roboshop

mkdir -p /app

curl -L -o /tmp/dispatch.zip https://roboshop-artifacts.s3.amazonaws.com/dispatch-v3.zip

cd /app
rm -rf /app/*
unzip -o /tmp/dispatch.zip

go mod init dispatch || true
go get
go build

validate $? "DISPATCH INSTALL"
