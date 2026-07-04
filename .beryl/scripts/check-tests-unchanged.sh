#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

source "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
tm_load_manifest_config "${REPO_ROOT}" "${BERYL_ROOT}"
tm_detect_hash_cmd

if [[ ! -f "${TM_MANIFEST_ABS}" ]]; then
  tm_fail "check-tests: missing ${TM_MANIFEST_REL}. Run .beryl/scripts/update-test-manifest.sh to create it."
fi

# Ensure the manifest matches the current configured test scope.
# This doesn't prevent edits; it detects them deterministically.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r rel; do
  [[ -z "${rel}" ]] && continue
  printf "%s  %s\n" "$(tm_hash_only "${REPO_ROOT}/${rel}")" "${rel}"
done < <(tm_collect_manifest_files "${REPO_ROOT}") >"$tmp"

if ! diff -u <(tm_normalize_manifest "${TM_MANIFEST_ABS}") <(tm_normalize_manifest "$tmp") >/dev/null; then
  tm_fail "check-tests: configured test scope differs from ${TM_MANIFEST_REL}. If intentional, run .beryl/scripts/update-test-manifest.sh and commit the updated manifest."
fi

printf "check-tests: OK (%s matches configured scope)\n" "${TM_MANIFEST_REL}"
