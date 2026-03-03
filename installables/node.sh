#!/bin/sh
set -eo pipefail

latest_version() {
  v=$(gh release view \
    --repo nodejs/node \
    --json tagName \
    --jq .tagName)
  echo "${v#v}"
}

v="${1:-$(latest_version)}"

cd "$(mktemp -d)"

curl -fsSL "https://nodejs.org/dist/${v}/node-${v}-darwin-arm64.tar.gz" -o node.tgz

# Avoid stale npm/corepack trees surviving tar extraction across upgrades.
$_SUDO rm -rf /usr/local/lib/node_modules/npm
$_SUDO rm -rf /usr/local/lib/node_modules/corepack
$_SUDO rm -rf /usr/local/include/node
$_SUDO rm -f /usr/local/bin/node
$_SUDO rm -f /usr/local/bin/npm
$_SUDO rm -f /usr/local/bin/npx
$_SUDO rm -f /usr/local/bin/corepack

# Install
$_SUDO tar -C /usr/local --strip-components=1 --no-same-owner -xzf ./node.tgz

# Clean up junk
$_SUDO rm /usr/local/CHANGELOG.md /usr/local/README.md /usr/local/LICENSE
$_SUDO rm -rf /usr/local/doc
