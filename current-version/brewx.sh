#!/bin/sh
set -euo pipefail

/usr/local/bin/brewx --version 2>/dev/null |
  /usr/bin/awk '
    /^brewx [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
