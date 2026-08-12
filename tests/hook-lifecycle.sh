#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-hook-lifecycle.XXXXXX")"
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

new_git_target() {
  local target="$1"
  mkdir -p "${target}/custom-hooks"
  git -C "${target}" init -q
  git -C "${target}" config user.email tests@example.invalid
  git -C "${target}" config user.name 'Beryl tests'
  printf '#!/bin/sh\nprintf custom-hook-ran > custom-hook-ran\n' >"${target}/custom-hooks/pre-commit"
  chmod +x "${target}/custom-hooks/pre-commit"
  git -C "${target}" config --local core.hooksPath custom-hooks
}

# Existing hook managers are an explicit conflict.  The safe default refuses
# before Beryl creates a control plane or changes the active hook.
fail_target="${TMP_DIR}/fail-target"
new_git_target "${fail_target}"
expect_failure "${TMP_DIR}/hook-conflict.out" sh "${REPO_ROOT}/install.sh" \
  --source-dir "${REPO_ROOT}" --target "${fail_target}" --profile standard --enable-githooks
assert_contains "${TMP_DIR}/hook-conflict.out" 'existing core.hooksPath conflict: custom-hooks'
[[ "$(git -C "${fail_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'default hook conflict changed the existing hook manager'
[[ ! -e "${fail_target}/.beryl" ]] || fail 'default hook conflict created a control plane'

# Preserve keeps the existing hook active and records both the decision and
# prior local value in the lifecycle lock.
preserve_target="${TMP_DIR}/preserve-target"
new_git_target "${preserve_target}"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${preserve_target}" \
  --profile standard --enable-githooks --hook-conflict preserve >"${TMP_DIR}/preserve.out" 2>&1
[[ "$(git -C "${preserve_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'preserve policy replaced the existing hook manager'
assert_contains "${preserve_target}/.beryl/lock.json" '"hookConflictPolicy": "preserve"'
assert_contains "${preserve_target}/.beryl/lock.json" '"githooksEnabled": false'
assert_contains "${preserve_target}/.beryl/lock.json" '"previousHooksPath": "custom-hooks"'
assert_contains "${TMP_DIR}/preserve.out" 'githooks were installed but are not active'
printf 'commit through custom hook\n' >"${preserve_target}/README.md"
git -C "${preserve_target}" add README.md
git -C "${preserve_target}" commit -qm 'prove custom hook still runs'
[[ -f "${preserve_target}/custom-hook-ran" ]] || fail 'preserved custom hook did not run'

# Replacement is the only policy that may change an existing hook manager,
# and it retains the old local value for rollback and later recovery.
replace_target="${TMP_DIR}/replace-target"
new_git_target "${replace_target}"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${replace_target}" \
  --profile standard --enable-githooks --hook-conflict replace
[[ "$(git -C "${replace_target}" config --local --get core.hooksPath)" == '.beryl/githooks' ]] || \
  fail 'replace policy did not activate Beryl githooks'
assert_contains "${replace_target}/.beryl/lock.json" '"hookConflictPolicy": "replace"'
assert_contains "${replace_target}/.beryl/lock.json" '"githooksEnabled": true'
assert_contains "${replace_target}/.beryl/lock.json" '"previousHooksPath": "custom-hooks"'

# Removing the githooks component restores the hook manager it displaced. A
# deselected runtime file is ambiguous target state, so it remains untouched
# but must leave Beryl's ownership ledger and cannot remain active.
replace_hook_before="${TMP_DIR}/replace-pre-commit.before"
cp "${replace_target}/.beryl/githooks/pre-commit" "${replace_hook_before}"
sh "${REPO_ROOT}/install.sh" --update --source-dir "${REPO_ROOT}" --target "${replace_target}" \
  --profile minimal
[[ "$(git -C "${replace_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'githooks downgrade did not restore the prior hook manager'
[[ -f "${replace_target}/.beryl/githooks/pre-commit" ]] || \
  fail 'githooks downgrade unexpectedly removed the ambiguous hook file'
cmp -s "${replace_hook_before}" "${replace_target}/.beryl/githooks/pre-commit" || \
  fail 'githooks downgrade changed the preserved ambiguous hook file'
! grep -Fq '.beryl/githooks/pre-commit' "${replace_target}/.beryl/lock.json" || \
  fail 'githooks downgrade kept the preserved hook file in the managed ledger'
rm -f "${replace_target}/custom-hook-ran"
printf 'prove restored hook manager\n' >"${replace_target}/README.md"
git -C "${replace_target}" add README.md
git -C "${replace_target}" commit -qm 'prove downgraded hook ownership'
[[ -f "${replace_target}/custom-hook-ran" ]] || \
  fail 'githooks downgrade left Beryl active instead of running the prior hook manager'

# A late failed downgrade restores Beryl's previous hook setting as part of
# the transaction rollback, rather than leaving a target in a mixed state.
rollback_target="${TMP_DIR}/rollback-target"
new_git_target "${rollback_target}"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${rollback_target}" \
  --profile standard --enable-githooks --hook-conflict replace
expect_failure "${TMP_DIR}/downgrade-rollback.out" env BERYL_UPDATE_FAIL_AT='verify:.beryl/agent/README.md' \
  sh "${REPO_ROOT}/install.sh" --update --source-dir "${REPO_ROOT}" --target "${rollback_target}" --profile minimal
assert_contains "${TMP_DIR}/downgrade-rollback.out" 'beryl: update failed phase=verify'
[[ "$(git -C "${rollback_target}" config --local --get core.hooksPath)" == '.beryl/githooks' ]] || \
  fail 'failed githooks downgrade did not restore the active Beryl hook setting'
[[ -x "${rollback_target}/.beryl/githooks/pre-commit" ]] || \
  fail 'failed githooks downgrade did not restore the hook file'

# Git worktrees use a .git file.  rev-parse still identifies them, so an
# explicit preserve policy must receive the same safe behavior.
main_repo="${TMP_DIR}/main-repo"
linked_worktree="${TMP_DIR}/linked-worktree"
mkdir -p "${main_repo}"
git -C "${main_repo}" init -q
git -C "${main_repo}" config user.email tests@example.invalid
git -C "${main_repo}" config user.name 'Beryl tests'
printf 'seed\n' >"${main_repo}/README.md"
git -C "${main_repo}" add README.md
git -C "${main_repo}" commit -qm seed
git -C "${main_repo}" worktree add --detach -q "${linked_worktree}"
git -C "${linked_worktree}" config --local core.hooksPath linked-hooks
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${linked_worktree}" \
  --profile standard --enable-githooks --hook-conflict preserve
[[ "$(git -C "${linked_worktree}" config --local --get core.hooksPath)" == 'linked-hooks' ]] || \
  fail 'linked worktree hook policy was not preserved'

printf 'hook lifecycle tests passed\n'
