#!/bin/bash
set -euo pipefail

PASSWORD="DevOps321"
REMOTE_USER="ec2-user"

SCRIPT_DIR=$(cd $(dirname "$0") && pwd)

dnf install -y sshpass unzip jq awscli >/dev/null 2>&1

declare -A HOSTS=(
[mongodb]="mongodb.sagar90s.online"
[redis]="redis.sagar90s.online"
[mysql]="mysql.sagar90s.online"
[rabbitmq]="rabbitmq.sagar90s.online"
[catalogue]="catalog.sagar90s.online"
[user]="user.sagar90s.online"
[cart]="cart.sagar90s.online"
[shipping]="shipping.sagar90s.online"
[payment]="payment.sagar90s.online"
)

DISPATCH_IP=$(aws ec2 describe-instances --instance-ids i-09cc18ef27c7d5216 --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

HOSTS[dispatch]=$DISPATCH_IP

ORDER=(mongodb redis mysql rabbitmq catalogue user cart shipping payment dispatch)

for COMPONENT in "${ORDER[@]}"
do
  HOST=${HOSTS[$COMPONENT]}

  sshpass -p "$PASSWORD" scp -o StrictHostKeyChecking=no   common.sh setup-${COMPONENT}.sh   ${REMOTE_USER}@${HOST}:/tmp/

  sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no   ${REMOTE_USER}@${HOST}   "echo '$PASSWORD' | sudo -S bash /tmp/setup-${COMPONENT}.sh"
done

sudo bash setup-frontend.sh
