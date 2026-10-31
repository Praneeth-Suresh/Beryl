#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

# Run every top-level tests/*.sh regression script. In a Git checkout only
# tracked scripts run, so stray local files cannot join the CI suite.
list_test_files() {
  if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -- ':(glob)tests/*.sh'
  else
    (cd "${REPO_ROOT}" && for file in tests/*.sh; do [[ -e "${file}" ]] && printf '%s\n' "${file}"; done)
  fi | LC_ALL=C sort
}

TEST_FILES=()
while IFS= read -r test_file; do
  [[ -n "${test_file}" ]] || continue
  case "/${test_file}/" in
    *'//'*|*'/./'*|*'/../'*)
      printf 'ERROR: unsafe shell test path: %s\n' "${test_file}" >&2
      exit 1
      ;;
  esac
  [[ -f "${REPO_ROOT}/${test_file}" && ! -L "${REPO_ROOT}/${test_file}" ]] || {
    printf 'ERROR: shell test must be a regular non-symlink file: %s\n' "${test_file}" >&2
    exit 1
  }
  [[ -r "${REPO_ROOT}/${test_file}" ]] || {
    printf 'ERROR: shell test must be readable: %s\n' "${test_file}" >&2
    exit 1
  }
  TEST_FILES+=("${test_file}")
done < <(list_test_files)
((${#TEST_FILES[@]} > 0)) || {
  printf 'ERROR: no shell regression tests found under tests/\n' >&2
  exit 1
}

for test_file in "${TEST_FILES[@]}"; do
  printf '==> %s\n' "${test_file}"
  bash "${REPO_ROOT}/${test_file}"
done

printf 'Executed %s shell regression test(s).\n' "${#TEST_FILES[@]}"
