#!/bin/sh
set -eo pipefail

staged_bin_dir="${PWD}/bin"
mkdir -p "${staged_bin_dir}"

yoink_path="$(
  curl -fsSL https://yoink.sh |
    sh -s -- -C "${staged_bin_dir}" mxcl/yoink |
    /usr/bin/head -n 1
)"

if [ -z "${yoink_path}" ] || ! [ -x "${yoink_path}" ]; then
  echo "yoink binary not found after download" >&2
  exit 1
fi

YOINK_BIN="${yoink_path}"
export YOINK_BIN

$_SUDO install -m 755 "${yoink_path}" /usr/local/bin/yoink
