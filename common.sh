#!/bin/bash

set -euo pipefail

LOG_FILE="/tmp/roboshop.log"

log() {
  echo -e "\e[32m[$(date '+%F %T')] $1\e[0m"
  echo "[$(date '+%F %T')] $1" >> ${LOG_FILE}
}

error() {
  echo -e "\e[31m[$(date '+%F %T')] ERROR: $1\e[0m"
  echo "[$(date '+%F %T')] ERROR: $1" >> ${LOG_FILE}
}

validate() {
  if [ $1 -ne 0 ]; then
    error "$2 FAILED"
    exit 1
  else
    log "$2 SUCCESS"
  fi
}
