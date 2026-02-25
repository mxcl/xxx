#!/bin/sh
set -euo pipefail

/usr/local/bin/caddy --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^v[0-9]+([.][0-9]+)+([[:space:]]|$)/) {
      value = substr($0, RSTART + 1, RLENGTH - 1)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
