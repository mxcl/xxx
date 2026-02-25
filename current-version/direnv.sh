#!/bin/sh
set -euo pipefail

/usr/local/bin/direnv --version 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
