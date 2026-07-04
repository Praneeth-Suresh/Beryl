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
CONFLICT_POLICY="${BERYL_SHIM_CONFLICT:-overwrite}"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

if [[ ! -f "${SOURCE}" ]]; then
  fail "missing source template: ${SOURCE}"
fi

case "${CONFLICT_POLICY}" in
  overwrite|skip|fail) ;;
  *) fail "BERYL_SHIM_CONFLICT must be overwrite, skip, or fail" ;;
esac

if [[ -e "${REPO_ROOT}/.codex" && ! -d "${REPO_ROOT}/.codex" ]]; then
  fail ".codex exists as a file. Remove or rename it, then rerun."
fi

targets=(
  "${REPO_ROOT}/AGENTS.md"
  "${REPO_ROOT}/CLAUDE.md"
  "${REPO_ROOT}/.cursor/rules/agent-rules.md"
  "${REPO_ROOT}/.github/copilot-instructions.md"
  "${REPO_ROOT}/.codex/AGENTS.md"
)

for target in "${targets[@]}"; do
  if [[ -f "${target}" ]] && cmp -s "${SOURCE}" "${target}"; then
    printf "already synced: %s\n" "${target#${REPO_ROOT}/}"
    continue
  fi

  if [[ -e "${target}" ]] && ! cmp -s "${SOURCE}" "${target}"; then
    case "${CONFLICT_POLICY}" in
      fail)
        fail "root shim conflict: ${target#${REPO_ROOT}/}. Re-run with BERYL_SHIM_CONFLICT=overwrite or skip."
        ;;
      skip)
        printf "skipped existing shim: %s\n" "${target#${REPO_ROOT}/}"
        continue
        ;;
    esac
  fi

  mkdir -p "$(dirname "${target}")"
  cp "${SOURCE}" "${target}"
  chmod 0644 "${target}"
  printf "synced: %s\n" "${target#${REPO_ROOT}/}"
done

printf "Sync complete. Canonical source: .beryl/agent/tool-instruction-template.md\n"
