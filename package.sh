#!/bin/zsh
# Package the extension into a .popclipextz file ready for release.
# Usage: zsh package.sh           → creates AIReply.popclipextz
#        zsh package.sh v1.2.3    → creates AIReply-v1.2.3.popclipextz

set -eu

cd "${0:A:h}"
ext_dir="AIReply.popclipext"
version="${1:-}"

if [[ ! -d "${ext_dir}" ]]; then
  echo "ERROR: ${ext_dir} not found." >&2
  exit 1
fi

out_name="AIReply"
[[ -n "${version}" ]] && out_name="${out_name}-v${version}"
out_file="${out_name}.popclipextz"

# Clean __pycache__ first.
find "${ext_dir}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# Create zip and rename to .popclipextz.
tmp_zip="/tmp/aireply_package_$$.zip"
rm -f "${tmp_zip}" "${out_file}"

cd "${ext_dir}"
zip -qr "${tmp_zip}" . -x '*.DS_Store' -x '*__pycache__*'
cd - >/dev/null

mv "${tmp_zip}" "${out_file}"
size="$(wc -c < "${out_file}" | tr -d ' ')"
echo "✓ ${out_file} (${size} bytes)"
echo "  Double-click to install in PopClip."
