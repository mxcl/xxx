#!/bin/sh
set -eo pipefail

cd "$(mktemp -d)"

/usr/local/bin/npm install -g --prefix "${PWD}" clawhub@${1:-latest}

# Upstream artifacts include 0600 files; normalize so non-root users can run.
chmod -R u+rwX,go+rX ./lib/node_modules/clawhub

$_SUDO rm -f /usr/local/bin/clawhub
$_SUDO rm -f /usr/local/bin/clawdhub
$_SUDO rm -rf /usr/local/lib/node_modules/clawhub
$_SUDO install -d -m 755 /usr/local/bin /usr/local/lib/node_modules
$_SUDO cp -RP ./lib/node_modules/clawhub /usr/local/lib/node_modules/clawhub
$_SUDO cp -RP ./bin/clawhub /usr/local/bin/clawhub
$_SUDO cp -RP ./bin/clawdhub /usr/local/bin/clawdhub
