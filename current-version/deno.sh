#!/bin/sh
set -euo pipefail

/usr/local/bin/deno --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^deno [0-9]+([.][0-9]+)+[[:space:]]*\(/) {
      value = substr($0, 6)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
