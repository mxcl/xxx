#!/bin/sh
set -euo pipefail

/usr/local/bin/node --version 2>/dev/null |
  /usr/bin/awk '
    /^v[0-9]+([.][0-9]+)+$/ {
      print substr($0, 2)
      exit
    }
  '
