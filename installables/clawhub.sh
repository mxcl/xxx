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

clawhub_version="${1:-latest}"
if [ -z "${clawhub_version}" ]; then
  clawhub_version="latest"
fi

case "${clawhub_version}" in
  v*) clawhub_version="${clawhub_version#v}" ;;
esac

package_spec="clawhub@${clawhub_version}"

prefix="${PWD}/clawhub.$$/prefix"
mkdir -p "${prefix}"
package_dir="${prefix}/lib/node_modules/clawhub"
staged_clawhub="${prefix}/bin/clawhub"
staged_clawdhub="${prefix}/bin/clawdhub"

if ! "${npm_bin}" install -g --prefix "${prefix}" "${package_spec}"; then
  echo "npm install failed via ${npm_bin}" >&2
  exit 1
fi

if ! [ -d "${package_dir}" ]; then
  echo "clawhub package was not staged at ${package_dir}" >&2
  exit 1
fi

if ! [ -e "${staged_clawhub}" ]; then
  echo "clawhub binary was not staged at ${staged_clawhub}" >&2
  exit 1
fi

chmod -R u+rwX,go+rX "${package_dir}"

$_SUDO rm -f /usr/local/bin/clawhub
$_SUDO rm -f /usr/local/bin/clawdhub
$_SUDO rm -rf /usr/local/lib/node_modules/clawhub
$_SUDO install -d -m 755 /usr/local/bin /usr/local/lib/node_modules
$_SUDO cp -RP "${package_dir}" /usr/local/lib/node_modules/clawhub
$_SUDO cp -RP "${staged_clawhub}" /usr/local/bin/clawhub

if [ -e "${staged_clawdhub}" ]; then
  $_SUDO cp -RP "${staged_clawdhub}" /usr/local/bin/clawdhub
fi
