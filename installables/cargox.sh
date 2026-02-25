#!/bin/sh
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink pkgxdev/cargox)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
