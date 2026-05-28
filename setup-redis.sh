#!/bin/bash
source /tmp/common.sh

dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm

dnf module enable redis:remi-7.2 -y

dnf install -y redis

sed -i 's/127.0.0.1/0.0.0.0/g' /etc/redis/redis.conf
sed -i 's/protected-mode yes/protected-mode no/g' /etc/redis/redis.conf

systemctl enable redis --now

validate $? "REDIS INSTALL"
