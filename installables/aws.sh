#!/bin/zsh
set -euo pipefail
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
  exit 1
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
trap cleanup EXIT

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
  exit 1
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
