#!/bin/sh
set -euo pipefail

bin="/usr/local/bin/caddy"
"${bin}" --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /v?[0-9]+([.][0-9]+)*/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^[^0-9]*/, "", value)
      sub(/[^0-9.].*$/, "", value)
      print value
      exit
    }
  '
