#!/bin/sh
set -euo pipefail

gh release view \
  --repo nodejs/node \
  --json tagName \
  --jq '.tagName | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
