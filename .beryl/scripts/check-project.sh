#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

# Project-specific extension point. The affected-test gate keeps commit-time
# feedback scoped to changed areas, while falling back to full tests for broad
# changes when a project test command is configured.
mode="${CHECK_AFFECTED_MODE:-worktree}"

case "${mode}" in
  staged)
    "${BERYL_ROOT}/scripts/check-affected.sh" --staged
    ;;
  worktree)
    "${BERYL_ROOT}/scripts/check-affected.sh" --worktree
    ;;
  base)
    if [[ -z "${CHECK_AFFECTED_BASE:-}" ]]; then
      printf "ERROR: CHECK_AFFECTED_BASE is required when CHECK_AFFECTED_MODE=base\n" >&2
      exit 1
    fi
    "${BERYL_ROOT}/scripts/check-affected.sh" --base "${CHECK_AFFECTED_BASE}"
    ;;
  *)
    printf "ERROR: unknown CHECK_AFFECTED_MODE: %s\n" "${mode}" >&2
    exit 1
    ;;
esac
