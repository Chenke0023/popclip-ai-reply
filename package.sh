#!/bin/zsh
# Package the extension into a .popclipextz file ready for release.
# Usage: zsh package.sh           → creates dist/AIReply-v0.1.0.popclipextz
#        zsh package.sh 1.2.3     → creates dist/AIReply-v1.2.3.popclipextz
#        zsh package.sh v1.2.3    → creates dist/AIReply-v1.2.3.popclipextz

set -eu

cd "${0:A:h}"
ext_dir="AIReply.popclipext"
version="${1:-0.1.0}"
version="${version#v}"
dist_dir="dist"
out_file="${dist_dir}/AIReply-v${version}.popclipextz"

if [[ ! -d "${ext_dir}" ]]; then
  echo "ERROR: ${ext_dir} not found." >&2
  exit 1
fi

mkdir -p "${dist_dir}"
rm -f "${out_file}"

# Clean transient files first.
find "${ext_dir}" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "${ext_dir}" -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
find "${ext_dir}" -name '.DS_Store' -delete 2>/dev/null || true

# PopClip packages are zip archives renamed to .popclipextz. Keep the
# .popclipext folder at the archive root for reliable double-click install.
if command -v ditto >/dev/null 2>&1; then
  ditto -c -k --sequesterRsrc --keepParent "${ext_dir}" "${out_file}"
else
  tmp_zip="/tmp/aireply_package_$$.zip"
  rm -f "${tmp_zip}"
  zip -qr "${tmp_zip}" "${ext_dir}" -x '*.DS_Store' -x '*__pycache__*' -x '*.pytest_cache*'
  mv "${tmp_zip}" "${out_file}"
fi

size="$(wc -c < "${out_file}" | tr -d ' ')"
echo "✓ ${out_file} (${size} bytes)"
echo "  Upload this file to the GitHub Release."
