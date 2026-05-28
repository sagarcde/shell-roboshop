#!/bin/bash
source /tmp/common.sh

curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash

dnf install -y rabbitmq-server

systemctl enable rabbitmq-server --now

rabbitmqctl add_user roboshop RoboShop@1 || true

rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"

validate $? "RABBITMQ INSTALL"
