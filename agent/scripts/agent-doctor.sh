#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE="${ROOT_DIR}/agent/tool-instruction-template.md"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

check_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path#${ROOT_DIR}/}"
}

check_exec() {
  local path="$1"
  [[ -x "${path}" ]] || fail "missing executable bit: ${path#${ROOT_DIR}/}"
}

printf "Checking agent workspace...\n"

required_canonical=(
  "${ROOT_DIR}/agent/README.md"
  "${ROOT_DIR}/agent/project-brief.md"
  "${ROOT_DIR}/agent/design-tree.md"
  "${ROOT_DIR}/agent/ubiquitous-language.md"
  "${ROOT_DIR}/agent/architecture.md"
  "${ROOT_DIR}/agent/testing-policy.md"
  "${ROOT_DIR}/agent/security-policy.md"
  "${ROOT_DIR}/agent/agent-rules.md"
  "${ROOT_DIR}/agent/task-routing.md"
  "${ROOT_DIR}/agent/tool-instruction-template.md"
  "${ROOT_DIR}/agent/test-manifest.conf"
  "${ROOT_DIR}/agent/mcp.json"
  "${ROOT_DIR}/agent/skills/planning/SKILL.md"
  "${ROOT_DIR}/agent/skills/adding-features/SKILL.md"
  "${ROOT_DIR}/agent/skills/debugging/SKILL.md"
  "${ROOT_DIR}/agent/skills/explaining-codebase/SKILL.md"
  "${ROOT_DIR}/agent/skills/grill-me/SKILL.md"
  "${ROOT_DIR}/agent/skills/interview-me/SKILL.md"
  "${ROOT_DIR}/agent/skills/testing-vertical-slices/SKILL.md"
  "${ROOT_DIR}/agent/skills/improving-architecture/SKILL.md"
  "${ROOT_DIR}/agent/skills/tracking-entropy/SKILL.md"
  "${ROOT_DIR}/agent/adr/0001-record-architecture-decisions.md"
)

for file in "${required_canonical[@]}"; do
  check_file "${file}"
done

required_exec=(
  "${ROOT_DIR}/agent/scripts/agent-doctor.sh"
  "${ROOT_DIR}/agent/scripts/sync-agent-env.sh"
  "${ROOT_DIR}/agent/scripts/entropy-hotspots.sh"
  "${ROOT_DIR}/scripts/check.sh"
  "${ROOT_DIR}/scripts/check-md.sh"
  "${ROOT_DIR}/scripts/check-tests-unchanged.sh"
  "${ROOT_DIR}/scripts/update-test-manifest.sh"
)

for file in "${required_exec[@]}"; do
  check_exec "${file}"
done

check_file "${ROOT_DIR}/scripts/test-manifest-lib.sh"
source "${ROOT_DIR}/scripts/test-manifest-lib.sh"
tm_load_manifest_config "${ROOT_DIR}"

command -v git >/dev/null 2>&1 || fail "git is not available on PATH"

if [[ -f "${ROOT_DIR}/.gitignore" ]]; then
  grep -qxF "agent/session-state.md" "${ROOT_DIR}/.gitignore" || fail ".gitignore must ignore agent/session-state.md"
else
  fail "missing file: .gitignore"
fi

if [[ -e "${ROOT_DIR}/.codex" && ! -d "${ROOT_DIR}/.codex" ]]; then
  fail ".codex must be a directory for generated shim output"
fi

shim_targets=(
  "${ROOT_DIR}/AGENTS.md"
  "${ROOT_DIR}/CLAUDE.md"
  "${ROOT_DIR}/.cursor/rules/agent-rules.md"
  "${ROOT_DIR}/.github/copilot-instructions.md"
  "${ROOT_DIR}/.codex/AGENTS.md"
)

for target in "${shim_targets[@]}"; do
  check_file "${target}"
  if ! cmp -s "${SOURCE}" "${target}"; then
    fail "stale shim: ${target#${ROOT_DIR}/}. Run agent/scripts/sync-agent-env.sh"
  fi
done

if [[ ! -f "${TM_MANIFEST_ABS}" ]]; then
  fail "${TM_MANIFEST_REL} is missing. Run scripts/update-test-manifest.sh"
fi

printf "Agent instruction files present.\n"
printf "Generated shims synchronized.\n"
printf "Deterministic check scripts available.\n"
