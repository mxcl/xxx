#!/bin/sh
set -euo pipefail

curl -fsSL https://formulae.brew.sh/api/formula/awscli.json | jq -r '.versions.stable'
