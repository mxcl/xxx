#!/bin/sh
set -eo pipefail

if ! [ -x /usr/local/bin/yoink ]; then
  curl -fsSL https://yoink.sh | sh -s -- mxcl/yoink
else
  /usr/local/bin/yoink mxcl/yoink
fi

$_SUDO install -m 755 ./yoink /usr/local/bin/yoink
