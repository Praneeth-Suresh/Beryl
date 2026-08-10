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
  [[ -f "${target}/LICENSE" ]] || fail "${profile}: Apache license missing"
  [[ -f "${target}/NOTICE" ]] || fail "${profile}: Apache notice missing"
  [[ -f "${target}/.beryl/agent/skills/initial-build/SKILL.md" ]] || \
    fail "${profile}: initial-build skill missing"
  [[ ! -e "${target}/.beryl/agent/hierarchy.md" ]] || \
    fail "${profile}: hierarchy.md must not be created during install"

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
[[ -f "${setup_target}/LICENSE" ]] || fail 'setup: Apache license missing'
[[ -f "${setup_target}/NOTICE" ]] || fail 'setup: Apache notice missing'
[[ -f "${setup_target}/tests/.manifest.sha256" ]] || fail 'setup: test manifest missing'
[[ -f "${setup_target}/.beryl/agent/skills/initial-build/SKILL.md" ]] || fail 'setup: initial-build skill missing'
[[ ! -e "${setup_target}/.beryl/agent/hierarchy.md" ]] || fail 'setup: hierarchy.md must not be created during install'

printf 'portability-smoke: PASS\n'
