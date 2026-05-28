#!/bin/bash
dnf install https://rpms.remirepo.net/enterprise/remi-release-9.rpm -y
dnf module enable redis:remi-7.2 -y
dnf install redis -y
sed -i 's/127.0.0.1/0.0.0.0/g' /etc/redis/redis.conf
systemctl enable redis --now
