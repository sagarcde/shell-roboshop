#!/bin/bash
set -euo pipefail

validate() {
  if [ $1 -ne 0 ]; then
    echo "FAILED : $2"
    exit 1
  else
    echo "SUCCESS : $2"
  fi
}
