#!/bin/bash
source /tmp/common.sh

dnf module disable mysql -y

cat >/etc/yum.repos.d/mysql.repo <<EOF
[mysql57-community]
name=MySQL 5.7 Community Server
baseurl=http://repo.mysql.com/yum/mysql-5.7-community/el/7/x86_64/
enabled=1
gpgcheck=0
EOF

dnf install -y mysql-community-server

systemctl enable mysqld --now

mysql_secure_installation --set-root-pass RoboShop@1 || true

validate $? "MYSQL INSTALL"
