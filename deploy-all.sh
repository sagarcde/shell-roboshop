#!/bin/bash

set -euo pipefail

PASSWORD="DevOps321"
REMOTE_USER="ec2-user"

SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

source ${SCRIPT_DIR}/common.sh

log "Installing required tools"
dnf install -y sshpass jq unzip awscli >/dev/null 2>&1
validate $? "INSTALL TOOLS"

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

deploy_component() {

  COMPONENT=$1
  HOST=$2

  log "Deploying ${COMPONENT} on ${HOST}"

  sshpass -p "${PASSWORD}" scp -o StrictHostKeyChecking=no \
    ${SCRIPT_DIR}/common.sh \
    ${SCRIPT_DIR}/setup-${COMPONENT}.sh \
    ${REMOTE_USER}@${HOST}:/tmp/

  validate $? "COPY ${COMPONENT}"

  sshpass -p "${PASSWORD}" ssh -tt \
    -o StrictHostKeyChecking=no \
    ${REMOTE_USER}@${HOST} \
    "echo '${PASSWORD}' | sudo -S bash /tmp/setup-${COMPONENT}.sh"

  validate $? "DEPLOY ${COMPONENT}"
}

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

log "Deploying frontend locally"

chmod +x ${SCRIPT_DIR}/setup-frontend.sh

echo "${PASSWORD}" | sudo -S bash ${SCRIPT_DIR}/setup-frontend.sh

validate $? "FRONTEND DEPLOYMENT"

log "ROBOSHOP DEPLOYMENT COMPLETED SUCCESSFULLY"
