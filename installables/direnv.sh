#!/bin/sh
set -eo pipefail

for path in $(/usr/local/bin/yoink direnv/direnv)
do
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done
