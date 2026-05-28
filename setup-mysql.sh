#!/bin/bash
source /tmp/common.sh
dnf module disable mysql -y
dnf install mysql-community-server -y
systemctl enable mysqld --now
mysql_secure_installation --set-root-pass RoboShop@1 || true
validate $? "MYSQL INSTALL"
