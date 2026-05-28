#!/bin/bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/erlang/script.rpm.sh | bash
curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.rpm.sh | bash
dnf install rabbitmq-server -y
systemctl enable rabbitmq-server --now
rabbitmqctl add_user roboshop RoboShop@1 || true
rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*"
