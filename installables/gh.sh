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

download_dir="${PWD}/gh.$$"
mkdir -p "${download_dir}"

paths="$("${yoink_bin}" -C "${download_dir}" cli/cli)"
if [ -z "${paths}" ]; then
  echo "Unable to download gh" >&2
  exit 1
fi

for path in ${paths}; do
  if [ -z "${path}" ] || ! [ -f "${path}" ]; then
    echo "gh binary not found after download" >&2
    exit 1
  fi
  $_SUDO install -m 755 "${path}" "/usr/local/bin/$(basename "${path}")"
done
