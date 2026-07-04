#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
source "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
tm_load_manifest_config "${REPO_ROOT}" "${BERYL_ROOT}"
tm_detect_hash_cmd

mkdir -p "$(dirname "${TM_MANIFEST_ABS}")"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r rel; do
  [[ -z "${rel}" ]] && continue
  printf "%s  %s\n" "$(tm_hash_only "${REPO_ROOT}/${rel}")" "${rel}"
done < <(tm_collect_manifest_files "${REPO_ROOT}") >"$tmp"

mv "$tmp" "${TM_MANIFEST_ABS}"
printf "Wrote %s\n" "${TM_MANIFEST_REL}"
