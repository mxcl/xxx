#!/bin/sh
set -euo pipefail

/usr/local/bin/gh --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^gh version [0-9]+([.][0-9]+)+[[:space:]]*\(/) {
      value = substr($0, 12)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
