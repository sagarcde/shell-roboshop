#!/bin/bash

source /tmp/common.sh

dnf module disable mysql -y

cat >/etc/yum.repos.d/mysql.repo <<EOF
[mysql80-community]
name=MySQL 8.0 Community Server
baseurl=https://repo.mysql.com/yum/mysql-8.0-community/el/9/x86_64/
enabled=1
gpgcheck=0
EOF

dnf install -y mysql-community-server

validate $? "MYSQL INSTALL"

systemctl enable mysqld --now

validate $? "MYSQL START"

mysql_secure_installation --set-root-pass RoboShop@1 || true

validate $? "MYSQL PASSWORD SET"