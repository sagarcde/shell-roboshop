#!/bin/bash
source ./common.sh
dnf install nginx -y
systemctl enable nginx --now
validate $? "FRONTEND INSTALL"
