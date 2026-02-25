#!/bin/sh
set -euo pipefail

/usr/local/bin/cargox --version 2>/dev/null |
  /usr/bin/awk '
    /^cargox [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
