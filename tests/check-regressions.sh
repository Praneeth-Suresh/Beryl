#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-check-regressions.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  local output="$1"
  shift
  if "$@" >"${output}" 2>&1; then
    fail "command unexpectedly succeeded: $*"
  fi
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${file}" || fail "${file} did not contain: ${expected}"
}

copy_check_surface() {
  local target="$1"
  mkdir -p "${target}"
  cp -R "${REPO_ROOT}/.beryl" "${target}/.beryl"
}

init_git_repo() {
  local target="$1"
  git -C "${target}" init -q
  git -C "${target}" config user.email 'beryl-tests@example.invalid'
  git -C "${target}" config user.name 'Beryl check regression tests'
}

# Root-level JavaScript, TypeScript, Python, and Go tests must be included in
# the immutable manifest just like their nested equivalents.
manifest_target="${TMP_DIR}/manifest"
copy_check_surface "${manifest_target}"
for rel in \
  root.test.js nested/root.test.js \
  root.spec.ts nested/root.spec.ts \
  test_root.py nested/test_root.py \
  root_test.py nested/root_test.py \
  root_test.go nested/root_test.go; do
  mkdir -p "${manifest_target}/$(dirname "${rel}")"
  printf 'test fixture: %s\n' "${rel}" >"${manifest_target}/${rel}"
done
(cd "${manifest_target}" && ./.beryl/scripts/update-test-manifest.sh)
for rel in \
  root.test.js nested/root.test.js \
  root.spec.ts nested/root.spec.ts \
  test_root.py nested/test_root.py \
  root_test.py nested/root_test.py \
  root_test.go nested/root_test.go; do
  assert_contains "${manifest_target}/tests/.manifest.sha256" "  ${rel}"
done
printf 'intentional root-level manifest mutation\n' >>"${manifest_target}/root.test.js"
expect_failure "${TMP_DIR}/manifest-changed.out" \
  bash "${manifest_target}/.beryl/scripts/check-tests-unchanged.sh"
assert_contains "${TMP_DIR}/manifest-changed.out" 'configured test scope differs'

# The affected-test gate shares the manifest glob matcher. Its recorder
# captures selected files instead of depending on a host project test runner.
affected_target="${TMP_DIR}/affected"
copy_check_surface "${affected_target}"
init_git_repo "${affected_target}"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\\n" "$@" > related-files.txt' \
  >"${affected_target}/related-test-recorder.sh"
chmod +x "${affected_target}/related-test-recorder.sh"
printf '%s\n' \
  'FULL_TEST_CMD=()' \
  'RELATED_TEST_CMD=("./related-test-recorder.sh")' \
  'GLOBAL_CHANGE_GLOBS=()' \
  'RELATED_CHANGE_GLOBS=(' \
  '  "*.test.*"' \
  '  "**/*.test.*"' \
  '  "*.spec.*"' \
  '  "**/*.spec.*"' \
  '  "*_test.go"' \
  '  "**/*_test.go"' \
  '  "test_*.py"' \
  '  "*_test.py"' \
  '  "**/test_*.py"' \
  '  "**/*_test.py"' \
  ')' \
  'IGNORED_CHANGE_GLOBS=()' \
  >"${affected_target}/.beryl/agent/affected-tests.conf"
git -C "${affected_target}" add .
git -C "${affected_target}" commit -qm 'baseline'
for rel in \
  root.test.js nested/root.test.js \
  root.spec.ts nested/root.spec.ts \
  test_root.py nested/test_root.py \
  root_test.py nested/root_test.py \
  root_test.go nested/root_test.go; do
  mkdir -p "${affected_target}/$(dirname "${rel}")"
  printf 'changed fixture: %s\n' "${rel}" >"${affected_target}/${rel}"
done
(cd "${affected_target}" && ./.beryl/scripts/check-affected.sh --worktree)
for rel in \
  root.test.js nested/root.test.js \
  root.spec.ts nested/root.spec.ts \
  test_root.py nested/test_root.py \
  root_test.py nested/root_test.py \
  root_test.go nested/root_test.go; do
  assert_contains "${affected_target}/related-files.txt" "${rel}"
done

write_markdown_fixture() {
  local target="$1"
  local content="$2"
  copy_check_surface "${target}"
  printf '%s\n' "${content}" >"${target}/fixture.md"
}

# Matching backtick and tilde fences may close with a longer marker run.
valid_markdown_target="${TMP_DIR}/markdown-valid"
write_markdown_fixture "${valid_markdown_target}" $'````lang\ncode\n`````\n\n~~~\ncode\n~~~~'
(cd "${valid_markdown_target}" && ./.beryl/scripts/check-md.sh)

# Tilde fences, mismatched markers, and shorter closing runs must fail rather
# than being hidden by the previous backtick-only count.
unclosed_tilde_target="${TMP_DIR}/markdown-unclosed-tilde"
write_markdown_fixture "${unclosed_tilde_target}" $'~~~\ncode'
expect_failure "${TMP_DIR}/markdown-unclosed-tilde.out" \
  bash "${unclosed_tilde_target}/.beryl/scripts/check-md.sh"
assert_contains "${TMP_DIR}/markdown-unclosed-tilde.out" 'Unclosed ~ code fence'

mismatched_marker_target="${TMP_DIR}/markdown-mismatched-marker"
write_markdown_fixture "${mismatched_marker_target}" $'```\ncode\n~~~'
expect_failure "${TMP_DIR}/markdown-mismatched-marker.out" \
  bash "${mismatched_marker_target}/.beryl/scripts/check-md.sh"
assert_contains "${TMP_DIR}/markdown-mismatched-marker.out" 'Unclosed ` code fence'

short_closer_target="${TMP_DIR}/markdown-short-closer"
write_markdown_fixture "${short_closer_target}" $'````\ncode\n```'
expect_failure "${TMP_DIR}/markdown-short-closer.out" \
  bash "${short_closer_target}/.beryl/scripts/check-md.sh"
assert_contains "${TMP_DIR}/markdown-short-closer.out" 'opened with 4 markers'

printf 'check regression tests passed\n'
