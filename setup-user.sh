#!/bin/bash
source /tmp/common.sh
dnf module disable nodejs -y
dnf module enable nodejs:20 -y
dnf install nodejs -y
validate $? "USER INSTALL"
