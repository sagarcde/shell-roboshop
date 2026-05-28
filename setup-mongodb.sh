#!/bin/bash
source /tmp/common.sh
dnf install -y mongodb-org
systemctl enable mongod --now
sed -i 's/127.0.0.1/0.0.0.0/' /etc/mongod.conf
systemctl restart mongod
validate $? "MONGODB INSTALL"
