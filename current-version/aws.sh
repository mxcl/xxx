#!/bin/sh
set -euo pipefail

/usr/local/bin/aws --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^aws-cli\/[0-9]+([.][0-9]+)+/) {
      value = substr($0, RSTART + 8, RLENGTH - 8)
      print value
      exit
    }
  '
