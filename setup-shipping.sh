#!/bin/bash
source /tmp/common.sh
dnf install maven -y
validate $? "SHIPPING INSTALL"
