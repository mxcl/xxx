#!/bin/sh
set -eo pipefail

aws_version="${1:-}"
if [ -z "${aws_version}" ]; then
  aws_version="$(
    curl -fsSL https://formulae.brew.sh/api/formula/awscli.json |
      /usr/local/bin/jq -r '.versions.stable'
  )"
fi

if [ -z "${aws_version}" ] || [ "${aws_version}" = "null" ]; then
  echo "Unable to determine latest awscli version" >&2
  exit 1
fi

stage_dir="${PWD}/aws.$$"
mkdir -p "${stage_dir}"

outdir="${stage_dir}/out"
root_group="$(id -gn root)"
build_script="${stage_dir}/build-aws.sh"
build_script_url="https://raw.githubusercontent.com/mxcl/bootstrap/refs/heads/main/build-aws.sh"

curl -fsSL "${build_script_url}" -o "${build_script}"
(
  cd "${stage_dir}"
  AWS_VERSION="${aws_version}" zsh "${build_script}"
)

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
