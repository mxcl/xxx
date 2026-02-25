#!/bin/sh
set -euo pipefail

/usr/local/bin/yoink -jI "pkgxdev/cargox" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
