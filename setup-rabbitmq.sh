#!/bin/bash
source /tmp/common.sh
dnf install rabbitmq-server -y
systemctl enable rabbitmq-server --now
rabbitmqctl add_user roboshop RoboShop@1 || true
rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"
validate $? "RABBITMQ INSTALL"
