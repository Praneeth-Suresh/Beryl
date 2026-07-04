#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/paths.sh
if [[ -f "${SCRIPT_DIR}/../../scripts/paths.sh" ]]; then
  source "${SCRIPT_DIR}/../../scripts/paths.sh"
else
  BERYL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  if command -v git >/dev/null 2>&1 && git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel)"
  else
    REPO_ROOT="$(cd "${BERYL_ROOT}/.." && pwd)"
  fi
fi
SOURCE="${BERYL_ROOT}/agent/tool-instruction-template.md"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

check_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path#${REPO_ROOT}/}"
}

check_exec() {
  local path="$1"
  [[ -x "${path}" ]] || fail "missing executable bit: ${path#${REPO_ROOT}/}"
}

printf "Checking agent workspace...\n"

required_canonical=(
  "${BERYL_ROOT}/agent/README.md"
  "${BERYL_ROOT}/agent/project-brief.md"
  "${BERYL_ROOT}/agent/design-tree.md"
  "${BERYL_ROOT}/agent/ubiquitous-language.md"
  "${BERYL_ROOT}/agent/architecture.md"
  "${BERYL_ROOT}/agent/testing-policy.md"
  "${BERYL_ROOT}/agent/security-policy.md"
  "${BERYL_ROOT}/agent/agent-rules.md"
  "${BERYL_ROOT}/agent/task-routing.md"
  "${BERYL_ROOT}/agent/tool-instruction-template.md"
  "${BERYL_ROOT}/agent/test-manifest.conf"
  "${BERYL_ROOT}/agent/affected-tests.conf"
  "${BERYL_ROOT}/agent/mcp.json"
  "${BERYL_ROOT}/agent/skills/planning/SKILL.md"
  "${BERYL_ROOT}/agent/skills/adding-features/SKILL.md"
  "${BERYL_ROOT}/agent/skills/debugging/SKILL.md"
  "${BERYL_ROOT}/agent/skills/explaining-codebase/SKILL.md"
  "${BERYL_ROOT}/agent/skills/grill-me/SKILL.md"
  "${BERYL_ROOT}/agent/skills/interview-me/SKILL.md"
  "${BERYL_ROOT}/agent/skills/testing-vertical-slices/SKILL.md"
  "${BERYL_ROOT}/agent/skills/improving-architecture/SKILL.md"
  "${BERYL_ROOT}/agent/skills/tracking-entropy/SKILL.md"
  "${BERYL_ROOT}/agent/adr/0001-record-architecture-decisions.md"
)

for file in "${required_canonical[@]}"; do
  check_file "${file}"
done

required_exec=(
  "${BERYL_ROOT}/agent/scripts/agent-doctor.sh"
  "${BERYL_ROOT}/agent/scripts/sync-agent-env.sh"
  "${BERYL_ROOT}/agent/scripts/entropy-hotspots.sh"
  "${BERYL_ROOT}/scripts/check.sh"
  "${BERYL_ROOT}/scripts/check-md.sh"
  "${BERYL_ROOT}/scripts/check-affected.sh"
  "${BERYL_ROOT}/scripts/check-tests-unchanged.sh"
  "${BERYL_ROOT}/scripts/setup-project.sh"
  "${BERYL_ROOT}/scripts/update-test-manifest.sh"
)

for file in "${required_exec[@]}"; do
  check_exec "${file}"
done

check_file "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
source "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
tm_load_manifest_config "${REPO_ROOT}" "${BERYL_ROOT}"

command -v git >/dev/null 2>&1 || fail "git is not available on PATH"

if [[ -f "${REPO_ROOT}/.gitignore" ]]; then
  grep -qxF ".beryl/agent/session-state.md" "${REPO_ROOT}/.gitignore" || fail ".gitignore must ignore .beryl/agent/session-state.md"
else
  fail "missing file: .gitignore"
fi

if [[ -e "${REPO_ROOT}/.codex" && ! -d "${REPO_ROOT}/.codex" ]]; then
  fail ".codex must be a directory for generated shim output"
fi

shim_targets=(
  "${REPO_ROOT}/AGENTS.md"
  "${REPO_ROOT}/CLAUDE.md"
  "${REPO_ROOT}/.cursor/rules/agent-rules.md"
  "${REPO_ROOT}/.github/copilot-instructions.md"
  "${REPO_ROOT}/.codex/AGENTS.md"
)

for target in "${shim_targets[@]}"; do
  check_file "${target}"
  if ! cmp -s "${SOURCE}" "${target}"; then
    fail "stale shim: ${target#${REPO_ROOT}/}. Run .beryl/agent/scripts/sync-agent-env.sh"
  fi
done

if [[ ! -f "${TM_MANIFEST_ABS}" ]]; then
  fail "${TM_MANIFEST_REL} is missing. Run .beryl/scripts/update-test-manifest.sh"
fi

printf "Agent instruction files present.\n"
printf "Generated shims synchronized.\n"
printf "Deterministic check scripts available.\n"
