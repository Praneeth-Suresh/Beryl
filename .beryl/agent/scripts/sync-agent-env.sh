#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

# This script writes root contracts, so it must establish its installed layout
# without first sourcing a helper or resolving a path through a symlink. The
# installer invokes it as ./.beryl/agent/scripts/sync-agent-env.sh; reject
# other invocation forms rather than guessing a repository root.
SCRIPT_PATH="${BASH_SOURCE[0]}"
case "${SCRIPT_PATH}" in
  /*) ;;
  *) SCRIPT_PATH="${PWD}/${SCRIPT_PATH}" ;;
esac
case "${SCRIPT_PATH}" in
  *'/../'*|*/..|../*|..) fail "script path must not contain .." ;;
esac

assert_no_symlink_path() {
  local path="$1" remaining segment walked
  case "${path}" in
    /*) ;;
    *) fail "internal path must be absolute: ${path}" ;;
  esac
  remaining="${path#/}"
  walked="/"
  while [[ -n "${remaining}" ]]; do
    segment="${remaining%%/*}"
    if [[ "${remaining}" == "${segment}" ]]; then
      remaining=""
    else
      remaining="${remaining#*/}"
    fi
    [[ -n "${segment}" ]] || continue
    walked="${walked%/}/${segment}"
    [[ ! -L "${walked}" ]] || fail "symlink is not allowed: ${walked}"
  done
}

assert_regular_source() {
  local path="$1"
  assert_no_symlink_path "${path}"
  [[ -f "${path}" ]] || fail "missing source template: ${path}"
}

assert_safe_target() {
  local target="$1" parent
  assert_no_symlink_path "${target}"
  parent="$(dirname "${target}")"
  while [[ "${parent}" != "/" ]]; do
    [[ ! -e "${parent}" || -d "${parent}" ]] || fail "shim parent is not a directory: ${parent}"
    parent="$(dirname "${parent}")"
  done
  if [[ -e "${target}" && ! -f "${target}" ]]; then
    fail "shim target is not a regular file: ${target}"
  fi
}

SCRIPT_DIR="$(dirname "${SCRIPT_PATH}")"
BERYL_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
REPO_ROOT="$(dirname "${BERYL_ROOT}")"
assert_no_symlink_path "${SCRIPT_PATH}"
assert_no_symlink_path "${BERYL_ROOT}"
assert_no_symlink_path "${REPO_ROOT}"

SOURCE="${BERYL_ROOT}/agent/tool-instruction-template.md"
CONFLICT_POLICY="${BERYL_SHIM_CONFLICT:-overwrite}"
assert_regular_source "${SOURCE}"

case "${CONFLICT_POLICY}" in
  overwrite|skip|fail) ;;
  *) fail "BERYL_SHIM_CONFLICT must be overwrite, skip, or fail" ;;
esac

targets=(
  "${REPO_ROOT}/AGENTS.md"
  "${REPO_ROOT}/CLAUDE.md"
  "${REPO_ROOT}/.cursor/rules/agent-rules.md"
  "${REPO_ROOT}/.github/copilot-instructions.md"
  "${REPO_ROOT}/.codex/AGENTS.md"
)

# Validate the complete write set before comparison or directory creation.
for target in "${targets[@]}"; do
  assert_safe_target "${target}"
done

for target in "${targets[@]}"; do
  if [[ -f "${target}" ]] && cmp -s "${SOURCE}" "${target}"; then
    printf 'already synced: %s\n' "${target#${REPO_ROOT}/}"
    continue
  fi

  if [[ -f "${target}" ]] && ! cmp -s "${SOURCE}" "${target}"; then
    case "${CONFLICT_POLICY}" in
      fail)
        fail "root shim conflict: ${target#${REPO_ROOT}/}. Re-run with BERYL_SHIM_CONFLICT=overwrite or skip."
        ;;
      skip)
        printf 'skipped existing shim: %s\n' "${target#${REPO_ROOT}/}"
        continue
        ;;
    esac
  fi

  mkdir -p "$(dirname "${target}")"
  cp "${SOURCE}" "${target}"
  chmod 0644 "${target}"
  printf 'synced: %s\n' "${target#${REPO_ROOT}/}"
done

printf 'Sync complete. Canonical source: .beryl/agent/tool-instruction-template.md\n'
