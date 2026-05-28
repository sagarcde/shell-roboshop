#!/bin/bash
source /tmp/common.sh

cat >/etc/yum.repos.d/mongo.repo <<EOF
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=0
enabled=1
EOF

dnf install -y mongodb-org
systemctl enable mongod --now
sed -i 's/127.0.0.1/0.0.0.0/' /etc/mongod.conf
systemctl restart mongod
