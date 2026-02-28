#!/bin/sh
set -eo pipefail

DEFAULT_PYTHON_VERSION="3.12"
PYTHON_VERSIONS="3.10 3.11 3.12 3.13"
TARGET_DIR="/usr/local/bin"
_SUDO=sudo

umask 022

if [ ! -d "${TARGET_DIR}" ]; then
  mkdir -p "${TARGET_DIR}"
fi

if [ ! -w "${TARGET_DIR}" ]; then
  printf '%s\n' "setup: ${TARGET_DIR} not writable; try running with sudo" >&2
  exit 1
fi

if [ ! -d /opt/homebrew ]; then
  user="${SUDO_USER:-${USER:-$(id -un)}}"

  install -d -o root -g wheel -m 0755 /opt/homebrew
  for x in     bin etc include lib sbin opt Cellar Caskroom Frameworks     share/zsh/site-functions var/homebrew/linked var/log
  do
    mkdir -p "/opt/homebrew/${x}"
  done

  chown -R "${user}:admin" /opt/homebrew
  chmod -R ug=rwx,go=rx /opt/homebrew
  chmod go-w /opt/homebrew/share/zsh /opt/homebrew/share/zsh/site-functions

  chown -R "${user}:admin" /opt/homebrew
fi

write_stub() {
  target="$1"
  cat >"${target}"
  chmod 755 "${target}"
}

install_python() {
  for version in ${PYTHON_VERSIONS}; do
    target="${TARGET_DIR}/python${version}"
    write_stub "${target}" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/bash

set -eo pipefail

_python_version=
if ! _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version" 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python "$_python_version"
  _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version")"
fi

exec "$_python_path" "$@"
__BOOTSTRAP_SCRIPT_EOF__
    sed -i '' "s|^_python_version=|_python_version=${version}|" "${target}"
  done

  rm -f "${TARGET_DIR}/python"
  ln -s "python3" "${TARGET_DIR}/python"

  rm -f "${TARGET_DIR}/python3"
  ln -s "python${DEFAULT_PYTHON_VERSION}" "${TARGET_DIR}/python3"
}

install_pip() {
  for version in ${PYTHON_VERSIONS}; do
    target="${TARGET_DIR}/pip${version}"
    write_stub "${target}" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

_python_version=

if ! _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version" 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python "$_python_version"
  _python_path="$(/usr/local/bin/uv python find --managed-python "$_python_version")"
fi

exec "$(dirname "$_python_path")"/pip "$@"
__BOOTSTRAP_SCRIPT_EOF__
    sed -i '' "s|^_python_version=|_python_version=${version}|" "${target}"
  done

  rm -f "${TARGET_DIR}/pip"
  ln -s "pip3" "${TARGET_DIR}/pip"

  rm -f "${TARGET_DIR}/pip3"
  ln -s "pip${DEFAULT_PYTHON_VERSION}" "${TARGET_DIR}/pip3"
}

install_python
install_pip

write_stub "${TARGET_DIR}/outdated" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/zsh
set -e

if [ "$(id -u)" -eq 0 ]; then
  echo "panic: do not run as root" >&2
  exit 1
fi

GUM_BIN="$(command -v gum 2>/dev/null || true)"
if [ -n "${GUM_BIN}" ] && ! "${GUM_BIN}" --version >/dev/null 2>&1; then
  GUM_BIN=
fi
OUTDATED_SELF="$0"

case "${OUTDATED_SELF}" in
  */*)
    ;;
  *)
    resolved_self="$(command -v "${OUTDATED_SELF}" 2>/dev/null || true)"
    if [ -n "${resolved_self}" ]; then
      OUTDATED_SELF="${resolved_self}"
    fi
    ;;
esac

if ! [ -x "${OUTDATED_SELF}" ]; then
  resolved_self="$(command -v outdated 2>/dev/null || true)"
  if [ -n "${resolved_self}" ]; then
    OUTDATED_SELF="${resolved_self}"
  fi
fi

gum() {
  if [ -n "${GUM_BIN}" ]; then
    "${GUM_BIN}" "$@"
  fi
}

is_internal_command() {
  case "$1" in
    uv_python_upgrade_available|rustup_upgrade_available|outdated_*|install_*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

is_known_install_target() {
  return 1
}

run_internal() {
  target="${1:-}"
  if [ -z "${target}" ]; then
    echo "panic: missing internal target" >&2
    exit 1
  fi
  shift

  if ! is_internal_command "${target}"; then
    echo "panic: unknown internal target: ${target}" >&2
    exit 1
  fi

  case "${target}" in
    outdated_*|install_*)
      OUTDATED_BOOTSTRAP_ONLY=1
      run_outdated >/dev/null
      ;;
  esac

  "${target}" "$@"
}

run_step() {
  title="$1"
  shift
  command_name="$1"
  shift

  if [ "${command_name}" = "sudo" ]; then
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
    return
  fi

  if is_internal_command "${command_name}"; then
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
    return
  fi

  if [ -n "${GUM_BIN}" ]; then
    gum spin --title "${title}" -- "${command_name}" "$@"
  else
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
  fi
}

run_step_capture() {
  title="$1"
  shift
  command_name="$1"
  shift

  if [ "${command_name}" = "sudo" ]; then
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
    return
  fi

  if is_internal_command "${command_name}"; then
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
    return
  fi

  if [ -n "${GUM_BIN}" ]; then
    gum spin --show-output --title "${title}" -- "${command_name}" "$@"
  else
    printf '# %s\n' "${title}" >&2
    "${command_name}" "$@"
  fi
}

shell_quote() {
  escaped="$(printf '%s' "$1" | /usr/bin/sed "s/'/'\\\\''/g")"
  printf "'%s'" "${escaped}"
}

queue_arg() {
  quoted="$(shell_quote "$1")"
  APPLY_ARGS="${APPLY_ARGS} ${quoted}"
  PLAN_HAS_ACTION=1
}

queue_brew_upgrade() {
  queue_arg "--brew"
}

queue_uv_python_upgrade() {
  queue_arg "--uv-python"
}

queue_rustup_upgrade() {
  queue_arg "--rustup"
}

queue_install() {
  name="$1"
  version="$2"
  if [ -z "${name}" ] || [ -z "${version}" ]; then
    return 0
  fi

  queue_arg "--install"
  queue_arg "${name}=${version}"
}

append_install_spec() {
  if [ -z "${REORDERED_INSTALL_QUEUE}" ]; then
    REORDERED_INSTALL_QUEUE="${1}"
  else
    REORDERED_INSTALL_QUEUE="${REORDERED_INSTALL_QUEUE}
${1}"
  fi
}

reorder_install_queue() {
  if [ -z "${INSTALL_QUEUE}" ]; then
    return 0
  fi

  REORDERED_INSTALL_QUEUE=""

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "yoink" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "deno" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "uv" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "aws" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    if [ "${name}" = "node" ]; then
      append_install_spec "${spec}"
    fi
  done <<EOF
${INSTALL_QUEUE}
EOF

  while IFS= read -r spec; do
    if [ -z "${spec}" ]; then
      continue
    fi
    name="${spec%%=*}"
    case "${name}" in
      yoink|deno|uv|aws|node)
        continue
        ;;
    esac
    append_install_spec "${spec}"
  done <<EOF
${INSTALL_QUEUE}
EOF

  INSTALL_QUEUE="${REORDERED_INSTALL_QUEUE}"
}

emit_plan() {
  if [ "${PLAN_HAS_ACTION}" -eq 0 ]; then
    return 0
  fi

  printf 'outdated --apply%s\n' "${APPLY_ARGS}"
}

begin_root_script() {
  ROOT_SCRIPT="${UPGRADE_STAGE_DIR}/root.sh"
  cat >"${ROOT_SCRIPT}" <<'EOF'
#!/bin/sh
set -e

apply_root_updates() {
EOF
  ROOT_COMMANDS_QUEUED=0
}

emit_root() {
  ROOT_COMMANDS_QUEUED=1

  sep=""
  printf '  ' >>"${ROOT_SCRIPT}"
  for arg in "$@"; do
    escaped="$(printf '%s' "${arg}" | /usr/bin/sed "s/'/'\\\\''/g")"
    printf "%s'%s'" "${sep}" "${escaped}" >>"${ROOT_SCRIPT}"
    sep=" "
  done
  printf '\n' >>"${ROOT_SCRIPT}"
}

apply_root_commands() {
  cat >>"${ROOT_SCRIPT}" <<'EOF'
}

apply_root_updates "$@"
EOF

  chmod 700 "${ROOT_SCRIPT}"

  if [ "${ROOT_COMMANDS_QUEUED}" -eq 0 ]; then
    return 0
  fi

  run_step "Applying privileged updates" sudo "${ROOT_SCRIPT}"
}

max_version() {
  best=""
  while IFS= read -r candidate; do
    if [ -z "${candidate}" ]; then
      continue
    fi
    if [ -z "${best}" ] || template_version_is_newer "${candidate}" "${best}"; then
      best="${candidate}"
    fi
  done
  printf '%s\n' "${best}"
}

template_sanitize_version() {
  printf '%s' "$1" | /usr/bin/sed -E 's/^[^0-9]*//; s/[^0-9.].*$//'
}

template_version_is_newer() {
  latest="$(template_sanitize_version "$1")"
  current="$(template_sanitize_version "$2")"

  if [ -z "${latest}" ] || [ -z "${current}" ]; then
    return 0
  fi

  /usr/bin/awk -v a="${latest}" -v b="${current}" '
    function splitver(v, arr,    i, n) {
      n = split(v, arr, ".");
      for (i = 1; i <= n; i++) if (arr[i] == "") arr[i] = 0;
      return n;
    }
    BEGIN {
      na = splitver(a, A);
      nb = splitver(b, B);
      n = (na > nb) ? na : nb;
      for (i = 1; i <= n; i++) {
        ai = (i <= na) ? A[i] : 0;
        bi = (i <= nb) ? B[i] : 0;
        if (ai + 0 > bi + 0) exit 0;
        if (ai + 0 < bi + 0) exit 1;
      }
      exit 2;
    }'

  case $? in
    0) return 0 ;;
    *) return 1 ;;
  esac
}

uv_python_upgrade_available() {
  if ! [ -x "/usr/local/bin/uv" ]; then
    return 1
  fi

  if ! command -v /usr/local/bin/jq >/dev/null 2>&1; then
    return 0
  fi

  installed_json="$(
    /usr/local/bin/uv python list --only-installed --output-format json \
      2>/dev/null || true
  )"
  if [ -z "${installed_json}" ] || [ "${installed_json}" = "[]" ]; then
    return 1
  fi

  minors="$(
    printf '%s' "${installed_json}" |
      /usr/local/bin/jq -r '
        .[] |
        select(.implementation == "cpython") |
        select(.path != null and (.path | contains("/.local/share/uv/python/"))) |
        "\(.version_parts.major).\(.version_parts.minor)"
      ' 2>/dev/null |
      /usr/bin/sort -u
  )"

  if [ -z "${minors}" ]; then
    return 1
  fi

  for minor in ${minors}; do
    installed_versions="$(
      printf '%s' "${installed_json}" |
        /usr/local/bin/jq -r --arg minor "${minor}" '
          .[] |
          select(.implementation == "cpython") |
          select(.path != null and (.path | contains("/.local/share/uv/python/"))) |
          select(
            ((.version_parts.major | tostring) + "." +
            (.version_parts.minor | tostring)) == $minor
          ) |
          .version
        ' 2>/dev/null
    )"
    current="$(printf '%s\n' "${installed_versions}" | max_version)"
    if [ -z "${current}" ]; then
      continue
    fi

    available_json="$(
      /usr/local/bin/uv python list "${minor}" --only-downloads --output-format \
        json 2>/dev/null || true
    )"
    if [ -z "${available_json}" ] || [ "${available_json}" = "[]" ]; then
      continue
    fi

    available_versions="$(
      printf '%s' "${available_json}" |
        /usr/local/bin/jq -r --arg minor "${minor}" '
          .[] |
          select(.implementation == "cpython") |
          select(
            ((.version_parts.major | tostring) + "." +
            (.version_parts.minor | tostring)) == $minor
          ) |
          .version
        ' 2>/dev/null
    )"
    latest="$(printf '%s\n' "${available_versions}" | max_version)"

    if [ -n "${latest}" ] && template_version_is_newer "${latest}" "${current}"; then
      return 0
    fi
  done

  return 1
}

rustup_upgrade_available() {
  if ! [ -x "$HOME/.cargo/bin/rustup" ]; then
    return 1
  fi

  if "$HOME/.cargo/bin/rustup" check 2>/dev/null |
    /usr/bin/grep -q "Update available"
  then
    return 0
  fi

  return 1
}

run_apply() {
  APPLY_BREW=0
  APPLY_UV_PYTHON=0
  APPLY_RUSTUP=0
  INSTALL_QUEUE=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --brew)
        APPLY_BREW=1
        ;;
      --uv-python)
        APPLY_UV_PYTHON=1
        ;;
      --rustup)
        APPLY_RUSTUP=1
        ;;
      --install)
        shift
        if [ $# -eq 0 ]; then
          echo "panic: --install requires NAME=VERSION" >&2
          exit 1
        fi
        if [ -z "${INSTALL_QUEUE}" ]; then
          INSTALL_QUEUE="$1"
        else
          INSTALL_QUEUE="${INSTALL_QUEUE}
$1"
        fi
        ;;
      *)
        echo "panic: unknown apply argument: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  UPGRADE_STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/upgrade.XXXXXX")"
  if ! [ -d "${UPGRADE_STAGE_DIR}" ]; then
    echo "panic: failed to create staging directory" >&2
    exit 1
  fi
  APPLY_ORIGINAL_PWD="$(pwd)"
  trap 'cd "${APPLY_ORIGINAL_PWD}" 2>/dev/null || true; rm -rf "${UPGRADE_STAGE_DIR}"' \
    EXIT

  if ! cd "${UPGRADE_STAGE_DIR}"; then
    echo "panic: failed to enter staging directory: ${UPGRADE_STAGE_DIR}" >&2
    exit 1
  fi

  run_step "Staging in ${UPGRADE_STAGE_DIR}" true
  begin_root_script
  _SUDO=emit_root

  if [ "${APPLY_BREW}" -eq 1 ] && [ -x "/opt/homebrew/bin/brew" ]; then
    run_step "Updating Homebrew" /opt/homebrew/bin/brew upgrade
  fi

  if [ "${APPLY_UV_PYTHON}" -eq 1 ] && [ -x "/usr/local/bin/uv" ]; then
    run_step "Updating Pythons" /usr/local/bin/uv python upgrade
  fi

  if [ "${APPLY_RUSTUP}" -eq 1 ] && [ -x "$HOME/.cargo/bin/rustup" ]; then
    run_step "Updating Rust" "$HOME/.cargo/bin/rustup" update
  fi

  if [ -n "${INSTALL_QUEUE}" ]; then
    reorder_install_queue

    while IFS= read -r spec; do
      if [ -z "${spec}" ]; then
        continue
      fi

      name="${spec%%=*}"
      version="${spec#*=}"
      if [ -z "${name}" ] || [ "${name}" = "${spec}" ] || [ -z "${version}" ]; then
        echo "panic: invalid install spec: ${spec}" >&2
        exit 1
      fi

      case "${name}" in
        *[!A-Za-z0-9_]*)
          echo "panic: invalid install target: ${name}" >&2
          exit 1
          ;;
      esac

      if ! is_known_install_target "${name}"; then
        echo "panic: unknown install target: ${name}" >&2
        exit 1
      fi

      install_func="install_${name}"
      run_step "Updating ${name}" "${install_func}" "${version}"
    done <<EOF
${INSTALL_QUEUE}
EOF
  fi

  apply_root_commands
}

run_outdated() {
  APPLY_ARGS=""
  PLAN_HAS_ACTION=0

  if [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then
    if [ -x "/opt/homebrew/bin/brew" ]; then
      if run_step "Checking Homebrew" /bin/sh -c \
        '[ -n "$(/opt/homebrew/bin/brew outdated 2>/dev/null)" ]'
      then
        queue_brew_upgrade
      fi
    fi

    if [ -x "/usr/local/bin/uv" ]; then
      if run_step "Checking Pythons" uv_python_upgrade_available; then
        queue_uv_python_upgrade
      fi
    fi

    if [ -x "$HOME/.cargo/bin/rustup" ]; then
      if run_step "Checking Rust" rustup_upgrade_available; then
        queue_rustup_upgrade
      fi
    fi
  fi


install_yoink() {
  version="$1"
set -eo pipefail

if ! [ -x /usr/local/bin/yoink ]; then
  curl -fsSL https://yoink.sh | sh -s -- mxcl/yoink
else
  /usr/local/bin/yoink mxcl/yoink
fi

$_SUDO install -m 755 ./yoink /usr/local/bin/yoink
}

install_deno() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink denoland/deno)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_uv() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink astral-sh/uv)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_aws() {
  version="$1"
setopt null_glob

aws_version="${1:-}"
if [[ -z "${aws_version}" ]]; then
  aws_version="$({
    curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
      /usr/local/bin/jq -r '.versions.stable'
  } 2>/dev/null || true)"
fi

if [[ -z "${aws_version}" || "${aws_version}" == "null" ]]; then
  echo "Unable to determine latest awscli version" >&2
  return 1
fi

stage_dir="${PWD}/aws.$$"
mkdir -p "${stage_dir}"
outdir="${stage_dir}/out"
root_group="$(id -gn root)"
mkdir -p "${outdir}"

prefix="$(realpath "${outdir}")"
share_dir="${prefix}/share/awscli"
bin_dir="${prefix}/bin"
python_version="3.12"
work_dir="$(mktemp -d -t aws-cli-build.XXXXXX)"
src_dir="${work_dir}/src"
archive_path="${work_dir}/aws-cli-${aws_version}.tar.gz"

cleanup() {
  rm -rf "${work_dir}" "${stage_dir}"
}

if [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then
  trap cleanup EXIT
fi

curl -fsSL \
  -A 'pkgx/manifests' \
  "https://github.com/aws/aws-cli/archive/${aws_version}.tar.gz" \
  -o "${archive_path}"

mkdir -p "${src_dir}"
tar -xzf "${archive_path}" --strip-components=1 -C "${src_dir}"

rm -rf "${prefix}"
mkdir -p "$(dirname "${share_dir}")" "${bin_dir}"

python_bin="$({ uv python find --managed-python "${python_version}"; } 2>/dev/null || true)"
if [[ -z "${python_bin}" ]]; then
  uv python install --managed-python "${python_version}"
  python_bin="$(uv python find --managed-python "${python_version}")"
fi
python_bin="$(realpath "${python_bin}")"

"${python_bin}" -m venv "${share_dir}"

venv_bin="${share_dir}/bin"
for name in python python3 "python${python_version}"; do
  rm -f "${venv_bin}/${name}"
  ln "${python_bin}" "${venv_bin}/${name}"
  chmod 755 "${venv_bin}/${name}" || true
done

python_prefix="$(dirname "$(dirname "${python_bin}")")"
lib_sources=("${python_prefix}"/lib/libpython*.dylib)
if (( ${#lib_sources[@]} == 0 )); then
  echo "missing libpython in ${python_prefix}/lib" >&2
  return 1
fi
mkdir -p "${share_dir}/lib"
for lib_source in "${lib_sources[@]}"; do
  lib_name="$(basename "${lib_source}")"
  rm -f "${share_dir}/lib/${lib_name}"
  ln "${lib_source}" "${share_dir}/lib/${lib_name}"
done

(
  cd "${src_dir}"
  "${share_dir}/bin/pip" install --no-cache-dir .
)

source_aws="${share_dir}/bin/aws"
out_aws="${bin_dir}/aws"
{
  cat <<'WRAPPER'
#!/bin/sh
""":"
d="$(cd "$(dirname "$0")/.." && pwd)"
exec "$d/share/awscli/bin/python" "$0" "$@"
":"""

WRAPPER
  tail -n +2 "${source_aws}"
} > "${out_aws}"
chmod 755 "${out_aws}"

for py_dir in "${share_dir}"/lib/python*; do
  [[ -d "${py_dir}" ]] || continue
  find "${py_dir}" -type f -name '*.h' -delete
  find "${py_dir}" -type d -name tests -prune -exec rm -rf {} +
  find "${py_dir}" -type d -name '__pycache__' -prune -exec rm -rf {} +

  site_packages="${py_dir}/site-packages"
  if [[ -d "${site_packages}" ]]; then
    rm -rf \
      "${site_packages}"/setuptools \
      "${site_packages}"/_distutils_hack \
      "${site_packages}"/pip \
      "${site_packages}"/pkg_resources \
      "${site_packages}"/pip-*.dist-info \
      "${site_packages}"/setuptools-*.dist-info \
      "${site_packages}"/wheel-*.dist-info
  fi
done

if [[ -d "${share_dir}/include" ]]; then
  for include_python in "${share_dir}"/include/python3*; do
    [[ -d "${include_python}" ]] || continue
    if [[ -z "$(ls -A "${include_python}")" ]]; then
      rm -rf "${include_python}"
    fi
  done

  if [[ -z "$(ls -A "${share_dir}/include")" ]]; then
    rm -rf "${share_dir}/include"
  fi
fi

if [[ -d "${share_dir}/bin" ]]; then
  find "${share_dir}/bin" -maxdepth 1 \
    \( -name 'activate' -o -name 'activate.*' -o -name 'pip*' -o -name 'easy_install*' \) \
    -exec rm -f {} +
fi

# prune junk
rm -rf "${outdir}/share/awscli/bin/aws"*
rm -rf "${outdir}/share/awscli/bin/__pycache__"
rm -f "${outdir}/share/awscli/bin/distro"
rm -f "${outdir}/share/awscli/bin/docutils"
rm -f "${outdir}/share/awscli/bin/jp.py"
rm -f "${outdir}/share/awscli/bin/rst"*

$_SUDO rm -f /usr/local/bin/aws
$_SUDO rm -rf /usr/local/share/awscli
$_SUDO install -d -m 755 /usr/local/bin /usr/local/share
$_SUDO mv "${outdir}/share/awscli" /usr/local/share/awscli
$_SUDO chown -R "root:${root_group}" /usr/local/share/awscli
$_SUDO install -m 755 "${outdir}/bin/aws" /usr/local/bin/aws
}

install_brewx() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink mxcl/brewx)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_caddy() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink caddyserver/caddy)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_cargox() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink pkgxdev/cargox)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_clawhub() {
  version="$1"
set -eo pipefail

npm_bin="${NPM_BIN:-/usr/local/bin/npm}"
if ! [ -x "${npm_bin}" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    echo "npm not installed; run installables/node.sh" >&2
    return 1
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
  return 1
fi

if ! [ -d "${package_dir}" ]; then
  echo "clawhub package was not staged at ${package_dir}" >&2
  return 1
fi

if ! [ -e "${staged_clawhub}" ]; then
  echo "clawhub binary was not staged at ${staged_clawhub}" >&2
  return 1
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
}

install_direnv() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink direnv/direnv)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_gh() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink cli/cli)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

install_node() {
  version="$1"
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
  return 1
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
}

install_openclaw() {
  version="$1"
set -eo pipefail

npm_bin="${NPM_BIN:-/usr/local/bin/npm}"
if ! [ -x "${npm_bin}" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    echo "npm not installed; run installables/node.sh" >&2
    return 1
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

prefix="${PWD}/openclaw.$$/prefix"
mkdir -p "${prefix}"
package_dir="${prefix}/lib/node_modules/openclaw"
staged_bin="${prefix}/bin/openclaw"

if ! "${npm_bin}" install -g --prefix "${prefix}" "${package_spec}"; then
  echo "npm install failed via ${npm_bin}" >&2
  return 1
fi

if ! [ -d "${package_dir}" ]; then
  echo "openclaw package was not staged at ${package_dir}" >&2
  return 1
fi

if ! [ -e "${staged_bin}" ]; then
  echo "openclaw binary was not staged at ${staged_bin}" >&2
  return 1
fi

# Upstream artifacts include 0600 files; normalize so non-root users can run.
chmod -R u+rwX,go+rX "${package_dir}"

$_SUDO rm -f /usr/local/bin/openclaw
$_SUDO rm -rf /usr/local/lib/node_modules/openclaw
$_SUDO install -d -m 755 /usr/local/bin /usr/local/lib/node_modules
$_SUDO cp -RP "${package_dir}" /usr/local/lib/node_modules/openclaw
$_SUDO cp -RP "${staged_bin}" /usr/local/bin/openclaw
}

install_pkgx() {
  version="$1"
set -eo pipefail

for artifact_path in $(/usr/local/bin/yoink pkgxdev/pkgx)
do
  $_SUDO install -m 755 "${artifact_path}" "/usr/local/bin/$(basename "${artifact_path}")"
done
}

is_known_install_target() {
  case "$1" in
    yoink)
      return 0
      ;;
    deno)
      return 0
      ;;
    uv)
      return 0
      ;;
    aws)
      return 0
      ;;
    brewx)
      return 0
      ;;
    caddy)
      return 0
      ;;
    cargox)
      return 0
      ;;
    clawhub)
      return 0
      ;;
    direnv)
      return 0
      ;;
    gh)
      return 0
      ;;
    node)
      return 0
      ;;
    openclaw)
      return 0
      ;;
    pkgx)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

current_version_yoink() {

/usr/local/bin/yoink --version 2>/dev/null |
  /usr/bin/awk '
    /^yoink [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
}

latest_version_yoink() {

/usr/local/bin/yoink -jI "mxcl/yoink" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_yoink() {
  if ! [ -x /usr/local/bin/yoink ]; then
    printf '%s\n' "latest"
    return 0
  fi
  latest="$(latest_version_yoink)" || return 1
  current="$(current_version_yoink || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_deno() {

/usr/local/bin/deno --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^deno [0-9]+([.][0-9]+)+[[:space:]]*\(/) {
      value = substr($0, 6)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
}

latest_version_deno() {

/usr/local/bin/yoink -jI "denoland/deno" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_deno() {
  latest="$(latest_version_deno)" || return 1
  current="$(current_version_deno || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_uv() {

/usr/local/bin/uv --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^uv [0-9]+([.][0-9]+)+([[:space:]]|$)/) {
      value = substr($0, 4)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
}

latest_version_uv() {

/usr/local/bin/yoink -jI "astral-sh/uv" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_uv() {
  latest="$(latest_version_uv)" || return 1
  current="$(current_version_uv || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_aws() {

/usr/local/bin/aws --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^aws-cli\/[0-9]+([.][0-9]+)+/) {
      value = substr($0, RSTART + 8, RLENGTH - 8)
      print value
      exit
    }
  '
}

latest_version_aws() {

curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
  /usr/local/bin/jq -r '.versions.stable'
}

outdated_aws() {
  latest="$(latest_version_aws)" || return 1
  current="$(current_version_aws || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_brewx() {

/usr/local/bin/brewx --version 2>/dev/null |
  /usr/bin/awk '
    /^brewx [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
}

latest_version_brewx() {

/usr/local/bin/yoink -jI "mxcl/brewx" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_brewx() {
  latest="$(latest_version_brewx)" || return 1
  current="$(current_version_brewx || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_caddy() {

/usr/local/bin/caddy --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^v[0-9]+([.][0-9]+)+([[:space:]]|$)/) {
      value = substr($0, RSTART + 1, RLENGTH - 1)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
}

latest_version_caddy() {

/usr/local/bin/yoink -jI "caddyserver/caddy" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_caddy() {
  latest="$(latest_version_caddy)" || return 1
  current="$(current_version_caddy || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_cargox() {

/usr/local/bin/cargox --version 2>/dev/null |
  /usr/bin/awk '
    /^cargox [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
}

latest_version_cargox() {

/usr/local/bin/yoink -jI "pkgxdev/cargox" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_cargox() {
  latest="$(latest_version_cargox)" || return 1
  current="$(current_version_cargox || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_clawhub() {

/usr/local/bin/clawhub -V 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
}

latest_version_clawhub() {

npm_bin="${NPM_BIN:-/usr/local/bin/npm}"
if ! [ -x "${npm_bin}" ]; then
  if command -v npm >/dev/null 2>&1; then
    npm_bin="$(command -v npm)"
  else
    return 1
  fi
fi

"${npm_bin}" view clawhub version 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
}

outdated_clawhub() {
  latest="$(latest_version_clawhub)" || return 1
  current="$(current_version_clawhub || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_direnv() {

/usr/local/bin/direnv --version 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
}

latest_version_direnv() {

/usr/local/bin/yoink -jI "direnv/direnv" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_direnv() {
  latest="$(latest_version_direnv)" || return 1
  current="$(current_version_direnv || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_gh() {

/usr/local/bin/gh --version 2>/dev/null |
  /usr/bin/awk '
    match($0, /^gh version [0-9]+([.][0-9]+)+[[:space:]]*\(/) {
      value = substr($0, 12)
      sub(/[[:space:]].*$/, "", value)
      print value
      exit
    }
  '
}

latest_version_gh() {

/usr/local/bin/yoink -jI "cli/cli" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_gh() {
  latest="$(latest_version_gh)" || return 1
  current="$(current_version_gh || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_node() {

/usr/local/bin/node --version 2>/dev/null |
  /usr/bin/awk '
    /^v[0-9]+([.][0-9]+)+$/ {
      print substr($0, 2)
      exit
    }
  '
}

latest_version_node() {

/usr/local/bin/yoink -jI "nodejs/node" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_node() {
  latest="$(latest_version_node)" || return 1
  current="$(current_version_node || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_openclaw() {

/usr/local/bin/openclaw --version 2>/dev/null |
  /usr/bin/awk '
    /^[0-9]+([.][0-9]+)+$/ {
      print $0
      exit
    }
  '
}

latest_version_openclaw() {

/usr/local/bin/yoink -jI "openclaw/openclaw" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_openclaw() {
  latest="$(latest_version_openclaw)" || return 1
  current="$(current_version_openclaw || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

current_version_pkgx() {

/usr/local/bin/pkgx --version 2>/dev/null |
  /usr/bin/awk '
    /^pkgx [0-9]+([.][0-9]+)+$/ {
      print $2
      exit
    }
  '
}

latest_version_pkgx() {

/usr/local/bin/yoink -jI "pkgxdev/pkgx" |
  /usr/local/bin/jq -r '.tag | sub("^[^0-9]*"; "") | sub("[^0-9.].*$"; "")'
}

outdated_pkgx() {
  latest="$(latest_version_pkgx)" || return 1
  current="$(current_version_pkgx || true)"
  if [ -z "${current}" ]; then
    printf '%s\n' "${latest}"
    return 0
  fi
  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then
    printf '%s\n' "${latest}"
    return 0
  fi
  return 1
}

if [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then

if version="$(run_step_capture "Checking yoink" outdated_yoink)"; then
  queue_install "yoink" "${version}"
fi

if version="$(run_step_capture "Checking deno" outdated_deno)"; then
  queue_install "deno" "${version}"
fi

if version="$(run_step_capture "Checking uv" outdated_uv)"; then
  queue_install "uv" "${version}"
fi

if version="$(run_step_capture "Checking aws" outdated_aws)"; then
  queue_install "aws" "${version}"
fi

if version="$(run_step_capture "Checking brewx" outdated_brewx)"; then
  queue_install "brewx" "${version}"
fi

if version="$(run_step_capture "Checking caddy" outdated_caddy)"; then
  queue_install "caddy" "${version}"
fi

if version="$(run_step_capture "Checking cargox" outdated_cargox)"; then
  queue_install "cargox" "${version}"
fi

if version="$(run_step_capture "Checking clawhub" outdated_clawhub)"; then
  queue_install "clawhub" "${version}"
fi

if version="$(run_step_capture "Checking direnv" outdated_direnv)"; then
  queue_install "direnv" "${version}"
fi

if version="$(run_step_capture "Checking gh" outdated_gh)"; then
  queue_install "gh" "${version}"
fi

if version="$(run_step_capture "Checking node" outdated_node)"; then
  queue_install "node" "${version}"
fi

if version="$(run_step_capture "Checking openclaw" outdated_openclaw)"; then
  queue_install "openclaw" "${version}"
fi

if version="$(run_step_capture "Checking pkgx" outdated_pkgx)"; then
  queue_install "pkgx" "${version}"
fi

  emit_plan
fi
}

if [ "${1:-}" = "--internal-run" ]; then
  shift
  run_internal "$@"
elif [ "${1:-}" = "--apply" ]; then
  shift
  OUTDATED_BOOTSTRAP_ONLY=1
  run_outdated >/dev/null
  run_apply "$@"
else
  run_outdated "$@"
fi
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/brew" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ ! -x /opt/homebrew/bin/brew ]; then
  if [ "$(id -u)" -eq 0 ]; then
    printf '%s\n' "brew: refusing to bootstrap /opt/homebrew as root" >&2
    exit 1
  fi

  cd /opt/homebrew
  git init -q
  git config remote.origin.url "https://github.com/Homebrew/brew"
  git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
  git config --bool fetch.prune true
  git config --bool core.autocrlf false
  git config --bool core.symlinks true

  git fetch --force --tags origin
  git remote set-head origin --auto >/dev/null || true

  latest_tag="$(git tag --list --sort='-version:refname' | head -n1)"
  git checkout -q -f -B stable "$latest_tag"

  /opt/homebrew/bin/brew update --force
fi

exec /opt/homebrew/bin/brew "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cargo" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed for this user" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

#TODO path might be different
source "$CARGO_HOME/env"

exec "$CARGO_HOME/bin/cargo" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cmake" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! cmake
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/code" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if ! [ -d /Applications/Visual\ Studio\ Code.app ]; then
  brew install --cask visual-studio-code
fi

exec /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/code_wait" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if ! [ -d /Applications/Visual\ Studio\ Code.app ]; then
  brew install --cask visual-studio-code
fi

exec /Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code --wait "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/codex" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask codex
fi

exec /opt/homebrew/bin/codex "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/cwebp" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! cwebp
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/ffmpeg" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! +ffmpeg-full ffmpeg
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/fork" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Fork.app ]; then
  /usr/local/bin/brew install --cask fork
fi

exec /Applications/Fork.app/Contents/Resources/fork_cli "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/git" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/git ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/git "$@"
fi

exec /usr/local/bin/brewx git "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/gum" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! gum
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/hyperfine" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh
exec /usr/local/bin/cargox hyperfine "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/jq" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/jq ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/jq "$@"
fi

exec /usr/local/bin/brewx jq "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/magick" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! magick
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/ollama" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

if [ ! -d /Applications/Ollama.app ]; then
  /usr/local/bin/brew install --cask ollama
fi

exec /Applications/Ollama.app/Contents/Resources/ollama "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/pip3.9" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/pip3 ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/pip3 "$@"
fi

if ! _python_path="$(/usr/local/bin/uv python find --managed-python 3.9 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python 3.9
  _python_path="$(/usr/local/bin/uv python find --managed-python 3.9)"
fi

exec "$(dirname "$_python_path")"/pip3 "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/python3.9" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

if [ -x /Library/Developer/CommandLineTools/usr/bin/python3 ]; then
  exec /Library/Developer/CommandLineTools/usr/bin/python3 "$@"
fi

if ! _python_path="$(/usr/local/bin/uv python find --managed-python 3.9 2>/dev/null)"; then
  /usr/local/bin/uv python install --managed-python 3.9
  _python_path="$(/usr/local/bin/uv python find --managed-python 3.9)"
fi

exec "$_python_path" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/rustc" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

#TODO path might be different
source "$CARGO_HOME/env"

exec "$CARGO_HOME/bin/rustc" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/rustup" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

set -eo pipefail

CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"

if [ ! -f "$CARGO_HOME/bin/rustup" -a "$1" = init ]; then
  # prevent rustup-init from warning that rust is already installed when it is just us
  export RUSTUP_INIT_SKIP_PATH_CHECK=yes

  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --no-modify-path
  exit $?
elif [ ! -f "$CARGO_HOME/bin/rustup" ]; then
  echo "a \`rustup\` toolchain has not been installed" >&2
  echo "run: \`rustup init\`" >&2
  exit 3
fi

exec "$CARGO_HOME/bin/rustup" "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/tailscale" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/bin/sh

# there's a kernel extension so the Mac App Store is the most secure choice

if ! [ -d /Applications/Tailscale.app ]; then
  brewx mas install 1475387142
fi

exec /Applications/Tailscale.app/Contents/MacOS/Tailscale "$@"
__BOOTSTRAP_SCRIPT_EOF__

write_stub "${TARGET_DIR}/xc" <<'__BOOTSTRAP_SCRIPT_EOF__'
#!/usr/bin/env -S brewx -! xc
__BOOTSTRAP_SCRIPT_EOF__
