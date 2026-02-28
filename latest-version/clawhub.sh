#!/bin/sh
set -euo pipefail

npm_bin="${NPM_BIN:-/usr/local/bin/npm}"
if ! [ -x "${npm_bin}" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    exit 1
  fi
fi

"${npm_bin}" view clawhub version 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
