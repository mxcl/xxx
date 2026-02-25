#!/bin/sh
set -euo pipefail

/usr/local/bin/yoink -jI "cli/cli" |
  /usr/bin/awk '
    found == 0 &&
    match($0, /"tag"[[:space:]]*:[[:space:]]*"[^"]+"/) {
      value = substr($0, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*"/, "", value)
      sub(/"$/, "", value)
      sub(/^[^0-9]*/, "", value)
      sub(/[^0-9.].*$/, "", value)
      print value
      found = 1
      exit
    }
  '
