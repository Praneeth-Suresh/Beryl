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

TEMPLATE_ROOT="${BERYL_ROOT}/agent/templates/install"
TARGET_ROOT="${BERYL_ROOT}/agent"
CONFLICT_POLICY="${BERYL_AGENT_TEMPLATE_CONFLICT:-skip}"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

case "${CONFLICT_POLICY}" in
  overwrite|skip|fail) ;;
  *) fail "BERYL_AGENT_TEMPLATE_CONFLICT must be overwrite, skip, or fail" ;;
esac

[[ -d "${TEMPLATE_ROOT}" ]] || fail "missing install templates: ${TEMPLATE_ROOT#${REPO_ROOT}/}"

while IFS= read -r source_file; do
  rel="${source_file#${TEMPLATE_ROOT}/}"
  target_file="${TARGET_ROOT}/${rel}"

  if [[ -f "${target_file}" ]] && cmp -s "${source_file}" "${target_file}"; then
    printf "already seeded: %s\n" "${target_file#${REPO_ROOT}/}"
    continue
  fi

  if [[ -e "${target_file}" ]] && ! cmp -s "${source_file}" "${target_file}" 2>/dev/null; then
    case "${CONFLICT_POLICY}" in
      fail)
        fail "agent context conflict: ${target_file#${REPO_ROOT}/}. Re-run with BERYL_AGENT_TEMPLATE_CONFLICT=overwrite or skip."
        ;;
      skip)
        printf "kept existing agent context: %s\n" "${target_file#${REPO_ROOT}/}"
        continue
        ;;
    esac
  fi

  mkdir -p "$(dirname "${target_file}")"
  cp "${source_file}" "${target_file}"
  chmod 0644 "${target_file}"
  printf "seeded: %s\n" "${target_file#${REPO_ROOT}/}"
done < <(find "${TEMPLATE_ROOT}" -type f | sort)

printf "Agent context seed complete. Template source: .beryl/agent/templates/install/\n"
