#!/bin/bash
source /tmp/common.sh
dnf install golang -y
validate $? "DISPATCH INSTALL"
