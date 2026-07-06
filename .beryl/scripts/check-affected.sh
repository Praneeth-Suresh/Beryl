#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
# shellcheck source=safe-conf.sh
source "${SCRIPT_DIR}/safe-conf.sh"
CONFIG_PATH="${BERYL_ROOT}/agent/affected-tests.conf"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  .beryl/scripts/check-affected.sh [--worktree|--staged|--base REF]

Modes:
  --worktree  Select tests from all changes relative to HEAD. Default.
  --staged    Select tests from staged changes only. Used by pre-commit.
  --base REF  Select tests from changes between REF and HEAD. Useful in CI.
USAGE
}

mode="worktree"
base_ref=""

while (($# > 0)); do
  case "$1" in
    --worktree)
      mode="worktree"
      shift
      ;;
    --staged)
      mode="staged"
      shift
      ;;
    --base)
      [[ $# -ge 2 ]] || fail "--base requires a ref"
      mode="base"
      base_ref="$2"
      shift 2
      ;;
    --base=*)
      mode="base"
      base_ref="${1#--base=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

FULL_TEST_CMD=()
RELATED_TEST_CMD=()
GLOBAL_CHANGE_GLOBS=()
RELATED_CHANGE_GLOBS=()
IGNORED_CHANGE_GLOBS=()

# Parsed as data, never sourced: a hostile .conf in a PR must not be able to
# execute shell in CI or at pre-commit.
sc_load_conf "${CONFIG_PATH}" \
  FULL_TEST_CMD RELATED_TEST_CMD \
  GLOBAL_CHANGE_GLOBS RELATED_CHANGE_GLOBS IGNORED_CHANGE_GLOBS

match_any() {
  local value="$1"
  shift
  local pattern
  for pattern in "$@"; do
    [[ "${value}" == ${pattern} ]] && return 0
  done
  return 1
}

collect_changed_files() {
  case "${mode}" in
    staged)
      git -C "${REPO_ROOT}" diff --cached --name-only --diff-filter=ACMR
      ;;
    worktree)
      if git -C "${REPO_ROOT}" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "${REPO_ROOT}" diff --name-only --diff-filter=ACMR HEAD
        git -C "${REPO_ROOT}" ls-files --others --exclude-standard
      else
        git -C "${REPO_ROOT}" ls-files
        git -C "${REPO_ROOT}" ls-files --others --exclude-standard
      fi
      ;;
    base)
      [[ -n "${base_ref}" ]] || fail "base ref is empty"
      git -C "${REPO_ROOT}" diff --name-only --diff-filter=ACMR "${base_ref}...HEAD"
      ;;
    *)
      fail "unknown mode: ${mode}"
      ;;
  esac
}

run_full_tests() {
  if ((${#FULL_TEST_CMD[@]} == 0)); then
    printf "check-affected: full test fallback selected, but FULL_TEST_CMD is not configured (OK: no project test runner yet)\n"
    return 0
  fi

  printf "check-affected: running full project tests: %s\n" "${FULL_TEST_CMD[*]}"
  "${FULL_TEST_CMD[@]}"
}

run_related_tests() {
  local files=("$@")

  if ((${#RELATED_TEST_CMD[@]} > 0)); then
    printf "check-affected: running related tests for %s changed file(s): %s\n" "${#files[@]}" "${RELATED_TEST_CMD[*]}"
    "${RELATED_TEST_CMD[@]}" "${files[@]}"
    return 0
  fi

  run_full_tests
}

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "check-affected: not a Git repository; using full test fallback\n"
  run_full_tests
  exit 0
fi

mapfile -t changed_files < <(collect_changed_files | LC_ALL=C sort -u)

if ((${#changed_files[@]} == 0)); then
  printf "check-affected: no changed files in %s mode (OK)\n" "${mode}"
  exit 0
fi

related_files=()

for rel in "${changed_files[@]}"; do
  [[ -z "${rel}" ]] && continue

  if ((${#GLOBAL_CHANGE_GLOBS[@]} > 0)) && match_any "${rel}" "${GLOBAL_CHANGE_GLOBS[@]}"; then
    printf "check-affected: global trigger changed: %s\n" "${rel}"
    run_full_tests
    exit 0
  fi

  if ((${#RELATED_CHANGE_GLOBS[@]} > 0)) && match_any "${rel}" "${RELATED_CHANGE_GLOBS[@]}"; then
    related_files+=("${rel}")
    continue
  fi

  if ((${#IGNORED_CHANGE_GLOBS[@]} > 0)) && match_any "${rel}" "${IGNORED_CHANGE_GLOBS[@]}"; then
    continue
  fi
done

if ((${#related_files[@]} == 0)); then
  printf "check-affected: no project test files selected from %s changed file(s) (OK)\n" "${#changed_files[@]}"
  exit 0
fi

run_related_tests "${related_files[@]}"
