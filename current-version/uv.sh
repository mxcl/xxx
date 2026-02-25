#!/bin/sh
set -euo pipefail

/usr/local/bin/uv --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^uv [0-9]+([.][0-9]+)+([[:space:]]|$)/) {
      value = substr($0, 4)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
