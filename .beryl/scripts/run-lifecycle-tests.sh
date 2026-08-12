#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

"${SCRIPT_DIR}/check-tests-unchanged.sh"

TEST_FILES=()
declare -A SEEN_TEST_FILES=()
MANIFEST_PATH="${REPO_ROOT}/tests/.manifest.sha256"

while IFS= read -r manifest_line || [[ -n "${manifest_line}" ]]; do
  [[ "${manifest_line}" =~ ^[0-9a-f]{64}[[:space:]][[:space:]](tests/.+\.sh)$ ]] || continue
  test_file="${BASH_REMATCH[1]}"

  case "${test_file}" in
    tests/*.sh) ;;
    *)
      printf 'ERROR: manifest shell test is outside tests/: %s\n' "${test_file}" >&2
      exit 1
      ;;
  esac
  case "/${test_file}/" in
    *'//'*|*'/./'*|*'/../'*)
      printf 'ERROR: unsafe manifest shell test path: %s\n' "${test_file}" >&2
      exit 1
      ;;
  esac
  [[ -n "${SEEN_TEST_FILES[${test_file}]:-}" ]] && {
    printf 'ERROR: duplicate manifest shell test path: %s\n' "${test_file}" >&2
    exit 1
  }
  SEEN_TEST_FILES["${test_file}"]=1
  [[ -f "${REPO_ROOT}/${test_file}" && ! -L "${REPO_ROOT}/${test_file}" ]] || {
    printf 'ERROR: manifest shell test must be a regular non-symlink file: %s\n' "${test_file}" >&2
    exit 1
  }
  [[ -r "${REPO_ROOT}/${test_file}" ]] || {
    printf 'ERROR: manifest shell test must be readable: %s\n' "${test_file}" >&2
    exit 1
  }
  TEST_FILES+=("${test_file}")
done < "${MANIFEST_PATH}"
((${#TEST_FILES[@]} > 0)) || {
  printf 'ERROR: no manifest-protected shell regression tests found under tests/\n' >&2
  exit 1
}

for test_file in "${TEST_FILES[@]}"; do
  printf '==> %s\n' "${test_file}"
  bash "${REPO_ROOT}/${test_file}"
done

printf 'Executed %s manifest-protected shell regression test(s).\n' "${#TEST_FILES[@]}"
