#!/bin/bash

set -eo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

list_installables() {
  if [ -f "${script_dir}/installables/yoink.sh" ]; then
    printf '%s\n' "${script_dir}/installables/yoink.sh"
  fi
  if [ -f "${script_dir}/installables/deno.sh" ]; then
    printf '%s\n' "${script_dir}/installables/deno.sh"
  fi
  if [ -f "${script_dir}/installables/uv.sh" ]; then
    printf '%s\n' "${script_dir}/installables/uv.sh"
  fi
  for x in "${script_dir}"/installables/*.sh; do
    if ! [ -e "${x}" ]; then
      continue
    fi
    case "$(basename "${x}")" in
    yoink.sh|deno.sh|uv.sh)
      continue
      ;;
    esac
    printf '%s\n' "${x}"
  done
}

emit_version_function() {
  local name="$1"
  local file="$2"

  printf '\n%s() {\n' "$name"
  /usr/bin/awk '
    NR == 1 && /^#!/ { next }
    /^set -euo pipefail$/ { next }
    /^script_path=/ { next }
    /^script_dir=/ { next }
    /script_dir/ { next }
    {
      sub(/exit /, "return ")
      if ($0 == "") { print ""; next }
      print "  " $0
    }
  ' "$file"
  printf '}\n'
}

emit_installable_function() {
  local name="$1"
  local file="$2"

  printf '\n%s() {\n' "$name"
  printf '  version="$1"\n'
  /usr/bin/awk '
    NR == 1 && /^#!/ { next }
    /^set -euo pipefail$/ { next }
    /^script_path=/ { next }
    /^script_dir=/ { next }
    /^outdated_script=/ { next }
    /^if ! version=/ { skipping = 1; next }
    /^version=/ {
      skipping_version = 1
      if ($0 ~ /\)"$/) { skipping_version = 0 }
      next
    }
    skipping {
      if ($0 ~ /^fi$/) { skipping = 0 }
      next
    }
    skipping_version {
      if ($0 ~ /\)"$/) { skipping_version = 0 }
      next
    }
    {
      sub(/exit /, "return ")
      if ($0 == "") { print ""; next }
      print "  " $0
    }
  ' "$file"
  printf '}\n'
}

emit_installable_target_matcher() {
  printf '\nis_known_install_target() {\n'
  printf '  case "$1" in\n'
  while IFS= read -r installable; do
    if [ -z "${installable}" ]; then
      continue
    fi
    name="$(basename "${installable%.*}")"
    printf '    %s)\n' "${name}"
    printf '      return 0\n'
    printf '      ;;\n'
  done < <(list_installables)
  printf '    *)\n'
  printf '      return 1\n'
  printf '      ;;\n'
  printf '  esac\n'
  printf '}\n'
}

cat "${script_dir}/outdated.sh.in"
printf '\n'

while IFS= read -r installable; do
  name="$(basename "${installable%.*}")"
  emit_installable_function "install_${name}" "${installable}"
done < <(list_installables)

emit_installable_target_matcher

while IFS= read -r installable; do
  name="$(basename "${installable%.*}")"
  emit_version_function "current_version_${name}" \
    "${script_dir}/current-version/${name}.sh"
  emit_version_function "latest_version_${name}" \
    "${script_dir}/latest-version/${name}.sh"

  printf '\noutdated_%s() {\n' "${name}"
  if [ "${name}" = "yoink" ]; then
    printf '  if ! [ -x /usr/local/bin/yoink ]; then\n'
    printf '    printf '\''%%s\\n'\'' "latest"\n'
    printf '    return 0\n'
    printf '  fi\n'
  fi
  printf '  latest="$(latest_version_%s)" || return 1\n' "${name}"
  printf '  current="$(current_version_%s || true)"\n' "${name}"
  printf '  if [ -z "${current}" ]; then\n'
  printf '    printf '\''%%s\\n'\'' "${latest}"\n'
  printf '    return 0\n'
  printf '  fi\n'
  printf '  if cargox semverator lt "${current}" "${latest}" >/dev/null 2>&1; then\n'
  printf '    printf '\''%%s\\n'\'' "${latest}"\n'
  printf '    return 0\n'
  printf '  fi\n'
  printf '  return 1\n'
  printf '}\n'
done < <(list_installables)

printf '\nif [ "${OUTDATED_BOOTSTRAP_ONLY:-0}" -ne 1 ]; then\n'

while IFS= read -r installable; do
  name="$(basename "${installable%.*}")"
  printf '\nif version="$(run_step_capture "Checking %s" outdated_%s)"; then\n' \
    "${name}" "${name}"
  printf '  queue_install "%s" "${version}"\n' "${name}"
  printf 'fi\n'
done < <(list_installables)

printf '\n  emit_plan\n'
printf 'fi\n'
printf '}\n\n'
cat <<'EOF'
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
EOF
