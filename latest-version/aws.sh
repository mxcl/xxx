#!/bin/sh
set -euo pipefail

curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
  /usr/local/bin/jq -r '.versions.stable'
