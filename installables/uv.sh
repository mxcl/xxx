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

download_dir="${PWD}/uv.$$"
mkdir -p "${download_dir}"

paths="$("${yoink_bin}" -C "${download_dir}" astral-sh/uv)"
if [ -z "${paths}" ]; then
  echo "Unable to download uv" >&2
  exit 1
fi

first_path=""
staged_uv_bin=""
for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "uv binary not found after download" >&2
    exit 1
  fi
  if [ -z "${first_path}" ]; then
    first_path="${path}"
  fi
  if [ "$(basename "${path}")" = "uv" ]; then
    staged_uv_bin="${path}"
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done

if [ -z "${staged_uv_bin}" ]; then
  staged_uv_bin="${first_path}"
fi

if [ -n "${staged_uv_bin}" ] && [ -x "${staged_uv_bin}" ]; then
  UV_BIN="${staged_uv_bin}"
  export UV_BIN
fi
