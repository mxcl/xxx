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

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  tmpdir="$(mktemp -d "${UPGRADE_STAGE_DIR}/openclaw.XXXXXX")"
else
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' EXIT
fi

prefix="${tmpdir}/prefix"
package_dir="${prefix}/lib/node_modules/openclaw"
staged_bin="${prefix}/bin/openclaw"

"${npm_bin}" install -g --prefix "${prefix}" "${package_spec}"

if ! [ -d "${package_dir}" ]; then
  echo "openclaw package was not staged at ${package_dir}" >&2
  exit 1
fi

if ! [ -e "${staged_bin}" ]; then
  echo "openclaw binary was not staged at ${staged_bin}" >&2
  exit 1
fi

$_SUDO install -d -m 755 /usr/local/bin /usr/local/lib/node_modules
$_SUDO rm -f /usr/local/bin/openclaw
$_SUDO rm -rf /usr/local/lib/node_modules/openclaw
$_SUDO cp -RP "${package_dir}" /usr/local/lib/node_modules/openclaw
$_SUDO cp -RP "${staged_bin}" /usr/local/bin/openclaw

if [ -n "${UPGRADE_STAGE_DIR:-}" ]; then
  $_SUDO rm -rf "${tmpdir}"
fi
