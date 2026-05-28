#!/bin/bash
source /tmp/common.sh
dnf install python3 gcc python3-devel -y
validate $? "PAYMENT INSTALL"
