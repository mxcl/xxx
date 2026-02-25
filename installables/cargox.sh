#!/bin/sh
set -eo pipefail

yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"

download_dir="${PWD}/cargox.$$"
mkdir -p "${download_dir}"

paths="$("${yoink_bin}" -C "${download_dir}" pkgxdev/cargox)"
if [ -z "${paths}" ]; then
  echo "Unable to download cargox" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "cargox binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done
