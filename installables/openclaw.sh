#!/bin/sh
set -eo pipefail

npm_bin="${NPM_BIN:-/usr/local/bin/npm}"
if ! [ -x "${npm_bin}" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    echo "npm not installed; run installables/node.sh" >&2
    exit 1
  fi
fi

openclaw_version="${1:-latest}"
if [ -z "${openclaw_version}" ]; then
  openclaw_version="latest"
fi

case "${openclaw_version}" in
  v*) openclaw_version="${openclaw_version#v}" ;;
esac

package_spec="openclaw@${openclaw_version}"
$_SUDO "${npm_bin}" install -g --prefix /usr/local "${package_spec}"
