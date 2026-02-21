#!/bin/sh
set -euo pipefail

script_path="$(command -v "$0" 2>/dev/null || printf '%s' "$0")"
script_dir="$(CDPATH= cd -- "$(dirname -- "${script_path}")" && pwd)"

. "${script_dir}/lib.sh"

check_outdated_with_yoink "astral-sh/uv" "/usr/local/bin/uv"
