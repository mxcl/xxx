#!/bin/sh
set -eo pipefail

yoink_bin="${YOINK_BIN:-/usr/local/bin/yoink}"
if ! [ -x "${yoink_bin}" ]; then
  if command -v yoink >/dev/null 2>&1; then
    yoink_bin="$(command -v yoink)"
  else
    echo "yoink not installed; run installables/yoink.sh" >&2
    exit 1
  fi
fi

download_dir="${PWD}/deno.$$"
mkdir -p "${download_dir}"

downloaded="$(
  "${yoink_bin}" -C "${download_dir}" denoland/deno |
    /usr/bin/head -n 1
)"

if [ -z "${downloaded}" ] || ! [ -f "${downloaded}" ]; then
  echo "deno binary not found after download" >&2
  exit 1
fi

staged_bin_dir="${PWD}/bin"
mkdir -p "${staged_bin_dir}"
staged_deno="${staged_bin_dir}/deno"
cp "${downloaded}" "${staged_deno}"
chmod 755 "${staged_deno}"
DENO_BIN="${staged_deno}"
export DENO_BIN

$_SUDO install -m 755 "${downloaded}" /usr/local/bin/deno
