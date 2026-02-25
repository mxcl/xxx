#!/bin/sh
set -eo pipefail



download_dir="${PWD}/direnv.$$"
mkdir -p "${download_dir}"

downloaded="$(
  /usr/local/bin/yoink -C "${download_dir}" direnv/direnv |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "direnv binary not found after download" >&2
  exit 1
fi

tmpbin="${download_dir}/direnv"
if [ "${downloaded}" != "${tmpbin}" ]; then
  mv "${downloaded}" "${tmpbin}"
fi

$_SUDO install -m 755 "${tmpbin}" /usr/local/bin/direnv
