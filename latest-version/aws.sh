#!/bin/sh
set -euo pipefail

curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
    /usr/bin/awk '
      found == 0 &&
      match($0, /"stable"[[:space:]]*:[[:space:]]*"[^"]+"/) {
        value = substr($0, RSTART, RLENGTH)
        sub(/^.*:[[:space:]]*"/, "", value)
        sub(/"$/, "", value)
        print value
        found = 1
      }'
