#!/bin/sh
set -euo pipefail

/usr/local/bin/yoink --version 2>/dev/null |
  /usr/bin/awk '
    /^yoink [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
