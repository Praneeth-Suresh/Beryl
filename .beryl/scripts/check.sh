#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

if [[ ! -x "${BERYL_ROOT}/scripts/check-md.sh" ]]; then
  fail "Missing .beryl/scripts/check-md.sh (or not executable)."
fi

if [[ ! -x "${BERYL_ROOT}/scripts/check-tests-unchanged.sh" ]]; then
  fail "Missing .beryl/scripts/check-tests-unchanged.sh (or not executable)."
fi

if [[ ! -x "${BERYL_ROOT}/scripts/check-project.sh" ]]; then
  fail "Missing .beryl/scripts/check-project.sh (or not executable)."
fi

if [[ ! -x "${BERYL_ROOT}/scripts/validate-components.sh" ]]; then
  fail "Missing .beryl/scripts/validate-components.sh (or not executable)."
fi

if [[ ! -x "${BERYL_ROOT}/scripts/check-secrets.sh" ]]; then
  fail "Missing .beryl/scripts/check-secrets.sh (or not executable)."
fi

printf "Running deterministic checks...\n"

"${BERYL_ROOT}/scripts/check-md.sh"
"${BERYL_ROOT}/scripts/validate-components.sh"
"${BERYL_ROOT}/scripts/check-secrets.sh" --selftest
if [[ "${CHECK_AFFECTED_MODE:-worktree}" == "staged" ]]; then
  "${BERYL_ROOT}/scripts/check-secrets.sh" --staged
else
  "${BERYL_ROOT}/scripts/check-secrets.sh" --worktree
fi
"${BERYL_ROOT}/scripts/check-tests-unchanged.sh"
"${BERYL_ROOT}/scripts/check-project.sh"

printf "OK\n"
