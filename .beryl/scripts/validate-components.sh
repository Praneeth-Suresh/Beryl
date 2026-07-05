#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
# shellcheck source=beryl-components.sh
source "${SCRIPT_DIR}/beryl-components.sh"

manifest="${1:-${BERYL_ROOT}/beryl.components.json}"
bc_validate_manifest "${manifest}"

# Owner-slug drift gate: any GitHub download URL for the Beryl repo must use
# the canonical owner, so a stale (claimable) slug can never ship as a default.
BERYL_CANONICAL_OWNER="Praneeth-Suresh"
check_owner_slug_drift() {
  local file="$1" hits
  [[ -f "${file}" ]] || return 0
  hits="$(grep -nE '(raw\.githubusercontent\.com|codeload\.github\.com)/[A-Za-z0-9._-]+/Beryl[/.]' "${file}" \
    | grep -vF "/${BERYL_CANONICAL_OWNER}/Beryl" || true)"
  if [[ -n "${hits}" ]]; then
    printf "ERROR: owner-slug drift in %s (expected %s/Beryl):\n%s\n" \
      "${file#${REPO_ROOT}/}" "${BERYL_CANONICAL_OWNER}" "${hits}" >&2
    exit 1
  fi
}
check_owner_slug_drift "${manifest}"
check_owner_slug_drift "${REPO_ROOT}/install.sh"
check_owner_slug_drift "${REPO_ROOT}/README.md"

printf "components: OK (%s)\n" "${manifest#${REPO_ROOT}/}"
