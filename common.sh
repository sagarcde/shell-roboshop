#!/bin/bash

set -e

LOG_FILE="/tmp/roboshop.log"

log() {
  echo -e "\e[32m[$(date)] $1\e[0m"
  echo "[$(date)] $1" >> $LOG_FILE
}

error() {
  echo -e "\e[31m[$(date)] ERROR: $1\e[0m"
  echo "[$(date)] ERROR: $1" >> $LOG_FILE
}

validate() {
  if [ $1 -ne 0 ]; then
    error "$2 FAILED"
    exit 1
  else
    log "$2 SUCCESS"
  fi
}
