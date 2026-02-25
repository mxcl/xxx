#!/bin/sh
set -eo pipefail

node_version="${1:-}"
if [ -z "${node_version}" ]; then
  node_version="$(
    curl -fsSL https://nodejs.org/dist/index.json |
      /usr/local/bin/jq -r '.[0].version'
  )"
fi

if [ -z "${node_version}" ] || [ "${node_version}" = "null" ]; then
  echo "Unable to determine latest node version" >&2
  exit 1
fi

case "${node_version}" in
  v*) version="${node_version}" ;;
  *) version="v${node_version}" ;;
esac

asset="node-${version}-darwin-arm64.tar.gz"
url="https://nodejs.org/dist/${version}/${asset}"

download_dir="${PWD}/node.$$"
mkdir -p "${download_dir}"

asset_path="${download_dir}/${asset}"
curl -fsSL "${url}" -o "${asset_path}"

# Avoid stale npm/corepack trees surviving tar extraction across upgrades.
$_SUDO rm -rf /usr/local/lib/node_modules/npm
$_SUDO rm -rf /usr/local/lib/node_modules/corepack
$_SUDO rm -rf /usr/local/include/node
$_SUDO rm -f /usr/local/bin/node
$_SUDO rm -f /usr/local/bin/npm
$_SUDO rm -f /usr/local/bin/npx
$_SUDO rm -f /usr/local/bin/corepack

$_SUDO tar -C /usr/local --strip-components=1 --no-same-owner \
  -xzf "${asset_path}"
$_SUDO rm /usr/local/CHANGELOG.md /usr/local/README.md /usr/local/LICENSE
$_SUDO rm -rf /usr/local/doc
