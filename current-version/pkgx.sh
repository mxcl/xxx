#!/bin/sh
set -euo pipefail

/usr/local/bin/pkgx --version 2>/dev/null |
  /usr/bin/awk '
    /^pkgx [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
