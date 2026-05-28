#!/bin/bash
cat >/etc/yum.repos.d/mysql.repo <<EOF
[mysql80-community]
name=MySQL 8.0 Community
baseurl=https://repo.mysql.com/yum/mysql-8.0-community/el/9/x86_64/
enabled=1
gpgcheck=0
EOF

dnf module disable mysql -y
dnf install mysql-community-server -y
systemctl enable mysqld --now
mysql_secure_installation --set-root-pass RoboShop@1 || true
