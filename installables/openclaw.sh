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

stage_from_registry() {
  curl_bin="${CURL_BIN:-/usr/bin/curl}"
  jq_bin="${JQ_BIN:-/usr/bin/jq}"
  if ! [ -x "${curl_bin}" ]; then
    if command -v curl >/dev/null 2>&1; then
      curl_bin="$(command -v curl)"
    else
      echo "curl not installed; unable to stage openclaw from registry" >&2
      return 1
    fi
  fi
  if ! [ -x "${jq_bin}" ]; then
    if command -v jq >/dev/null 2>&1; then
      jq_bin="$(command -v jq)"
    else
      echo "jq not installed; unable to stage openclaw from registry" >&2
      return 1
    fi
  fi

  metadata="$("${curl_bin}" -fsSL \
    "https://registry.npmjs.org/openclaw/${openclaw_version}")"
  tarball_url="$(printf '%s' "${metadata}" | "${jq_bin}" -r '.dist.tarball')"
  bin_rel="$(
    printf '%s' "${metadata}" |
      "${jq_bin}" -r 'if (.bin | type) == "string"
        then .bin
        elif (.bin | type) == "object"
        then .bin.openclaw // empty
        else empty
        end'
  )"
  if [ -z "${tarball_url}" ] || [ "${tarball_url}" = "null" ]; then
    echo "Unable to determine openclaw tarball URL" >&2
    return 1
  fi
  if [ -z "${bin_rel}" ] || [ "${bin_rel}" = "null" ]; then
    echo "Unable to determine openclaw bin path from registry metadata" >&2
    return 1
  fi

  rm -rf "${prefix}"
  tarball_path="${tmpdir}/openclaw.tgz"
  extract_dir="${tmpdir}/extract"
  mkdir -p "${extract_dir}" "${package_dir}" "${prefix}/bin"
  "${curl_bin}" -fsSL "${tarball_url}" -o "${tarball_path}"
  tar -xzf "${tarball_path}" -C "${extract_dir}"
  if ! [ -d "${extract_dir}/package" ]; then
    echo "openclaw package payload not found in tarball" >&2
    return 1
  fi
  cp -RP "${extract_dir}/package/." "${package_dir}"

  case "${bin_rel}" in
    ./*) bin_rel="${bin_rel#./}" ;;
  esac
  if ! [ -f "${package_dir}/${bin_rel}" ]; then
    echo "openclaw bin entry not found: ${bin_rel}" >&2
    return 1
  fi
  ln -sf "../lib/node_modules/openclaw/${bin_rel}" "${staged_bin}"
}

if ! "${npm_bin}" install -g --prefix "${prefix}" "${package_spec}"; then
  echo "npm install failed, falling back to registry tarball staging" >&2
  stage_from_registry
fi

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
