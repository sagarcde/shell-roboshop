#!/bin/bash

set -e

PASSWORD="DevOps321"
REMOTE_USER="ec2-user"

SCRIPT_DIR=$(cd $(dirname $0); pwd)

source ${SCRIPT_DIR}/common.sh

dnf install -y sshpass jq awscli >/dev/null 2>&1

if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
fi

declare -A HOSTS=(
  [catalogue]="catalog.sagar90s.online"
  [user]="user.sagar90s.online"
  [cart]="cart.sagar90s.online"
  [shipping]="shipping.sagar90s.online"
  [payment]="payment.sagar90s.online"
  [mongodb]="mongodb.sagar90s.online"
  [redis]="redis.sagar90s.online"
  [mysql]="mysql.sagar90s.online"
  [rabbitmq]="rabbitmq.sagar90s.online"
)

DISPATCH_IP=$(aws ec2 describe-instances \
--instance-ids i-09cc18ef27c7d5216 \
--query 'Reservations[0].Instances[0].PrivateIpAddress' \
--output text)

HOSTS[dispatch]=$DISPATCH_IP

copy_ssh_key() {

  HOST=$1

  sshpass -p "$PASSWORD" ssh-copy-id \
  -o StrictHostKeyChecking=no \
  ${REMOTE_USER}@${HOST}

  validate $? "SSH KEY COPY TO ${HOST}"
}

deploy_component() {

  COMPONENT=$1
  HOST=$2

  log "Deploying ${COMPONENT} on ${HOST}"

  scp -o StrictHostKeyChecking=no \
  ${SCRIPT_DIR}/common.sh \
  ${SCRIPT_DIR}/setup-${COMPONENT}.sh \
  ${REMOTE_USER}@${HOST}:/tmp/

  validate $? "COPY ${COMPONENT}"

  ssh -o StrictHostKeyChecking=no \
  ${REMOTE_USER}@${HOST} \
  "chmod +x /tmp/setup-${COMPONENT}.sh && sudo bash /tmp/setup-${COMPONENT}.sh"

  validate $? "DEPLOY ${COMPONENT}"
}

for COMPONENT in "${!HOSTS[@]}"
do
  copy_ssh_key ${HOSTS[$COMPONENT]}
done

DEPLOY_ORDER=(
  mongodb
  redis
  mysql
  rabbitmq
  catalogue
  user
  cart
  shipping
  payment
  dispatch
)

for COMPONENT in "${DEPLOY_ORDER[@]}"
do
  deploy_component ${COMPONENT} ${HOSTS[$COMPONENT]}
done

chmod +x setup-frontend.sh
sudo bash setup-frontend.sh

validate $? "FRONTEND DEPLOYMENT"

log "ROBOSHOP DEPLOYMENT COMPLETED"
