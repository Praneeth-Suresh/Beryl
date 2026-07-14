#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-portability.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

install_profile() {
  local profile="$1"
  local target="${TMP_DIR}/${profile}"

  sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${target}" --profile "${profile}"
  [[ -f "${target}/.beryl/lock.json" ]] || fail "${profile}: lockfile was not written"
  [[ -f "${target}/AGENTS.md" ]] || fail "${profile}: generated shim missing"

  if [[ "${profile}" != "minimal" ]]; then
    (cd "${target}" && ./.beryl/scripts/check.sh)
  fi

  if [[ "${profile}" == "full" ]]; then
    (cd "${target}" && DRIVER_MOCK=1 bash .beryl/driver/run.sh --selftest)
    (cd "${target}" && bash .beryl/driver/optimize-worktrees.sh --selftest)
  fi
}

install_profile minimal
install_profile standard
install_profile full

setup_target="${TMP_DIR}/setup"
mkdir -p "${setup_target}"
printf 'n\nn\n1\n1\ny\nn\n' | \
  bash "${REPO_ROOT}/.beryl/scripts/setup-project.sh" --profile standard "${setup_target}"
[[ -x "${setup_target}/.beryl/scripts/check.sh" ]] || fail 'setup: check.sh missing'
[[ -f "${setup_target}/AGENTS.md" ]] || fail 'setup: generated shim missing'
[[ -f "${setup_target}/tests/.manifest.sha256" ]] || fail 'setup: test manifest missing'

printf 'portability-smoke: PASS\n'
