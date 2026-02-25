#!/bin/sh
set -eo pipefail

yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"

download_dir="${PWD}/caddy.$$"
mkdir -p "${download_dir}"

paths="$("${yoink_bin}" -C "${download_dir}" caddyserver/caddy)"
if [ -z "${paths}" ]; then
  echo "Unable to download caddy" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "caddy binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done
