#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${REPO_ROOT}/.beryl/scripts/setup-project.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-setup-lifecycle.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local expected="$2"
  grep -Fq -- "${expected}" "${file}" || fail "${file} did not contain: ${expected}"
}

expect_status() {
  local expected="$1"
  local output="$2"
  shift 2
  if "$@" >"${output}" 2>&1; then
    actual=0
  else
    actual=$?
  fi
  [[ "${actual}" -eq "${expected}" ]] || fail "expected exit ${expected}, got ${actual}: $*"
}

expect_interactive_eof() {
  local input="$1"
  local target="$2"
  local output="$3"
  local actual

  if printf '%b' "${input}" | bash "${SETUP_SCRIPT}" >"${output}" 2>&1; then
    actual=0
  else
    actual="${PIPESTATUS[1]}"
  fi
  [[ "${actual}" -eq 1 ]] || fail "expected interactive EOF exit 1, got ${actual}"
  [[ ! -e "${target}/.beryl" ]] || fail "interactive EOF mutated target before lifecycle delegation: ${target}"
  [[ ! -e "${target}/.beryl/lock.json" ]] || fail "interactive EOF wrote a lockfile: ${target}"
}

make_git_target_with_existing_hooks() {
  local target="$1"
  git init -q "${target}"
  git -C "${target}" config core.hooksPath custom-hooks
}

# CI must run the same manifest-protected shell regression surface that contains these
# lifecycle tests. Keep this source-level assertion local to the setup slice
# so a workflow edit cannot silently remove the Ubuntu regression job.
assert_contains "${REPO_ROOT}/.github/workflows/deterministic-checks.yml" \
  './.beryl/scripts/run-lifecycle-tests.sh'
assert_contains "${REPO_ROOT}/.beryl/scripts/run-lifecycle-tests.sh" \
  'check-tests-unchanged.sh'
assert_contains "${REPO_ROOT}/.beryl/scripts/run-lifecycle-tests.sh" \
  'tests/.manifest.sha256'
assert_contains "${REPO_ROOT}/.beryl/scripts/run-lifecycle-tests.sh" \
  'bash "${REPO_ROOT}/${test_file}"'
assert_contains "${REPO_ROOT}/.beryl/scripts/run-lifecycle-tests.sh" \
  'manifest shell test must be a regular non-symlink file'
assert_contains "${REPO_ROOT}/.beryl/scripts/run-lifecycle-tests.sh" \
  'manifest shell test must be readable'

# A non-interactive standard setup must create the same lifecycle lock as a
# direct install, and that lock must immediately support a normal update.
standard_target="${TMP_DIR}/standard target"
expect_status 0 "${TMP_DIR}/standard.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --skip-check "${standard_target}" </dev/null
[[ -f "${standard_target}/.beryl/lock.json" ]] || fail 'standard setup did not create a lockfile'
assert_contains "${TMP_DIR}/standard.out" 'setup-project: lifecycle transaction committed'
expect_status 0 "${TMP_DIR}/standard-update.out" \
  sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --update --target "${standard_target}"
expect_status 0 "${TMP_DIR}/setup-repeat.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --skip-check "${standard_target}" </dev/null
assert_contains "${TMP_DIR}/setup-repeat.out" 'setup-project: delegating locked target update'

# Setup must not replace a lock-recorded root conflict policy with its new
# target default. A target-owned root shim skipped at installation remains
# target-owned when setup delegates the locked update without an override.
root_skip_target="${TMP_DIR}/root-skip"
mkdir -p "${root_skip_target}"
printf 'target-owned AGENTS contract\n' >"${root_skip_target}/AGENTS.md"
expect_status 0 "${TMP_DIR}/root-skip-install.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile minimal --root-conflict skip --skip-check "${root_skip_target}" </dev/null
assert_contains "${root_skip_target}/.beryl/lock.json" '"rootConflictPolicy": "skip"'
[[ "$(<"${root_skip_target}/AGENTS.md")" == 'target-owned AGENTS contract' ]] || \
  fail 'initial root skip did not preserve the target-owned AGENTS contract'
expect_status 0 "${TMP_DIR}/root-skip-update.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --skip-check "${root_skip_target}" </dev/null
assert_contains "${TMP_DIR}/root-skip-update.out" 'setup-project: delegating locked target update'
[[ "$(<"${root_skip_target}/AGENTS.md")" == 'target-owned AGENTS contract' ]] || \
  fail 'locked setup update replaced a skipped target-owned AGENTS contract'
assert_contains "${root_skip_target}/.beryl/lock.json" '"rootConflictPolicy": "skip"'

# --non-interactive must fail before mutation when its required target is
# absent, and it must not consume stdin for component or stack choices.
missing_target="${TMP_DIR}/missing-target"
expect_status 1 "${TMP_DIR}/missing-target.out" \
  bash "${SETUP_SCRIPT}" --non-interactive </dev/null
assert_contains "${TMP_DIR}/missing-target.out" '--non-interactive requires TARGET_DIR'
[[ ! -e "${missing_target}" ]] || fail 'missing target case mutated a target'

stdin_target="${TMP_DIR}/stdin-closed"
expect_status 0 "${TMP_DIR}/stdin-closed.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile minimal --skip-check "${stdin_target}" </dev/null
[[ -f "${stdin_target}/.beryl/lock.json" ]] || fail 'closed-stdin setup did not finish'

# Interactive setup collects every choice before it delegates the lifecycle
# transaction. EOF during the component, root policy, stack/test adapter, or
# check prompts therefore cannot create a control plane or lock.
eof_components_target="${TMP_DIR}/eof-components"
expect_interactive_eof "${eof_components_target}\n" "${eof_components_target}" "${TMP_DIR}/eof-components.out"
assert_contains "${TMP_DIR}/eof-components.out" 'input ended while choosing: Choose the Beryl component set'

eof_root_target="${TMP_DIR}/eof-root"
expect_interactive_eof "${eof_root_target}\n1\n" "${eof_root_target}" "${TMP_DIR}/eof-root.out"
assert_contains "${TMP_DIR}/eof-root.out" 'input ended while choosing: Choose how to handle existing root contracts'

eof_stack_target="${TMP_DIR}/eof-stack"
expect_interactive_eof "${eof_stack_target}\n1\n1\nn\n" "${eof_stack_target}" "${TMP_DIR}/eof-stack.out"
assert_contains "${TMP_DIR}/eof-stack.out" 'input ended while choosing: Choose the closest project stack'

eof_custom_command_target="${TMP_DIR}/eof-custom-command"
expect_interactive_eof "${eof_custom_command_target}\n1\n1\nn\n4\n1\n" \
  "${eof_custom_command_target}" "${TMP_DIR}/eof-custom-command.out"
assert_contains "${TMP_DIR}/eof-custom-command.out" 'input ended while reading: RELATED_TEST_CMD'

eof_check_target="${TMP_DIR}/eof-check"
expect_interactive_eof "${eof_check_target}\n1\n1\nn\n4\n2\nn\n" \
  "${eof_check_target}" "${TMP_DIR}/eof-check.out"
assert_contains "${TMP_DIR}/eof-check.out" 'input ended while reading: Run ./.beryl/scripts/check.sh in the target now?'

# A completed interactive custom path forwards the selected component set and
# writes only its collected adapter configuration after the lifecycle commits.
interactive_custom_target="${TMP_DIR}/interactive-custom"
expect_status 0 "${TMP_DIR}/interactive-custom.out" \
  bash -c 'printf "%b" "$1" | bash "$2"' bash \
  "${interactive_custom_target}\\n4\\nagent-core,checks\\n1\\nn\\n4\\n1\\n(printf related)\\n(printf full)\\nn\\nn\\n" \
  "${SETUP_SCRIPT}"
assert_contains "${interactive_custom_target}/.beryl/lock.json" '"requestedComponents": ["agent-core","checks"]'
assert_contains "${interactive_custom_target}/.beryl/agent/affected-tests.conf" 'RELATED_TEST_CMD=(printf related)'
assert_contains "${interactive_custom_target}/.beryl/agent/affected-tests.conf" 'FULL_TEST_CMD=(printf full)'

# The same invariant holds for an existing target: prompt cancellation cannot
# add Beryl files or change its existing Git hook configuration.
eof_existing_target="${TMP_DIR}/eof-existing"
make_git_target_with_existing_hooks "${eof_existing_target}"
printf 'target-owned sentinel\n' >"${eof_existing_target}/sentinel.txt"
expect_interactive_eof "${eof_existing_target}\n1\n" "${eof_existing_target}" "${TMP_DIR}/eof-existing.out"
[[ "$(<"${eof_existing_target}/sentinel.txt")" == 'target-owned sentinel' ]] || \
  fail 'interactive EOF changed existing target content'
[[ "$(git -C "${eof_existing_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'interactive EOF changed existing Git configuration'

# Git reports linked worktrees through rev-parse even though .git is a file.
git_main="${TMP_DIR}/git-main"
git_worktree="${TMP_DIR}/git-worktree"
git init -q "${git_main}"
git -C "${git_main}" config user.email test@example.invalid
git -C "${git_main}" config user.name 'Beryl test'
printf 'seed\n' >"${git_main}/README.md"
git -C "${git_main}" add README.md
git -C "${git_main}" commit -qm seed
git -C "${git_main}" worktree add --detach -q "${git_worktree}"
[[ -f "${git_worktree}/.git" ]] || fail 'fixture did not create a linked-worktree .git file'
expect_status 0 "${TMP_DIR}/linked-worktree.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile minimal --skip-check "${git_worktree}" </dev/null
assert_contains "${TMP_DIR}/linked-worktree.out" 'Git repository detected (including linked worktrees)'
[[ -z "$(git -C "${git_worktree}" config --local --get core.hooksPath || true)" ]] || \
  fail 'setup changed core.hooksPath in a linked worktree'

# Hook configuration stays inside the lifecycle engine. Setup's safe default
# leaves an existing hook manager untouched; enabling it forwards the explicit
# conflict policy and preserves the install transaction's no-mutation refusal.
hooks_default_target="${TMP_DIR}/hooks-default"
make_git_target_with_existing_hooks "${hooks_default_target}"
expect_status 0 "${TMP_DIR}/hooks-default.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile standard --skip-check "${hooks_default_target}" </dev/null
[[ "$(git -C "${hooks_default_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'default setup replaced an existing hook manager'
assert_contains "${hooks_default_target}/.beryl/lock.json" '"githooksEnabled": false'

hooks_fail_target="${TMP_DIR}/hooks-fail"
make_git_target_with_existing_hooks "${hooks_fail_target}"
expect_status 1 "${TMP_DIR}/hooks-fail.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile standard --skip-check \
  --enable-githooks "${hooks_fail_target}" </dev/null
assert_contains "${TMP_DIR}/hooks-fail.out" 'existing core.hooksPath conflict: custom-hooks'
[[ "$(git -C "${hooks_fail_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'failed hook enablement changed an existing hook manager'
[[ ! -e "${hooks_fail_target}/.beryl" ]] || fail 'failed hook enablement mutated the control plane'

hooks_preserve_target="${TMP_DIR}/hooks-preserve"
make_git_target_with_existing_hooks "${hooks_preserve_target}"
expect_status 0 "${TMP_DIR}/hooks-preserve.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile standard --skip-check \
  --enable-githooks --hook-conflict preserve "${hooks_preserve_target}" </dev/null
[[ "$(git -C "${hooks_preserve_target}" config --local --get core.hooksPath)" == 'custom-hooks' ]] || \
  fail 'preserved hook policy changed an existing hook manager'
assert_contains "${hooks_preserve_target}/.beryl/lock.json" '"hookConflictPolicy": "preserve"'
assert_contains "${hooks_preserve_target}/.beryl/lock.json" '"githooksEnabled": false'

hooks_replace_target="${TMP_DIR}/hooks-replace"
make_git_target_with_existing_hooks "${hooks_replace_target}"
expect_status 0 "${TMP_DIR}/hooks-replace.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile standard --skip-check \
  --enable-githooks --hook-conflict replace "${hooks_replace_target}" </dev/null
[[ "$(git -C "${hooks_replace_target}" config --local --get core.hooksPath)" == '.beryl/githooks' ]] || \
  fail 'replace hook policy did not activate Beryl hooks'
assert_contains "${hooks_replace_target}/.beryl/lock.json" '"hookConflictPolicy": "replace"'
assert_contains "${hooks_replace_target}/.beryl/lock.json" '"githooksEnabled": true'
assert_contains "${hooks_replace_target}/.beryl/lock.json" '"previousHooksPath": "custom-hooks"'

# A post-install deterministic check is not part of the lifecycle transaction:
# it returns a distinct failure but leaves the valid lock committed for update.
failing_source="${TMP_DIR}/failing-source"
late_check_target="${TMP_DIR}/late-check-target"
mkdir -p "${failing_source}"
cp -pR "${REPO_ROOT}/." "${failing_source}/"
printf '#!/usr/bin/env bash\nprintf "forced check failure\\n" >&2\nexit 73\n' >"${failing_source}/.beryl/scripts/check.sh"
chmod +x "${failing_source}/.beryl/scripts/check.sh"
expect_status 2 "${TMP_DIR}/late-check.out" \
  bash "${failing_source}/.beryl/scripts/setup-project.sh" --non-interactive --profile standard --run-check "${late_check_target}" </dev/null
assert_contains "${TMP_DIR}/late-check.out" 'lifecycle is committed; deterministic check failed'
[[ -f "${late_check_target}/.beryl/lock.json" ]] || fail 'late check failure removed the committed lock'
expect_status 0 "${TMP_DIR}/late-check-update.out" \
  sh "${failing_source}/install.sh" --source-dir "${failing_source}" --update --target "${late_check_target}"

# Bootstrap is a second, standalone setup action. Its failure must happen only
# after the lifecycle update commits: the installed bootstrap script sees the
# new lock, its updated bytes remain present, and a subsequent normal update
# can use that committed state. This guards against treating arbitrary agent
# side effects as rollback-safe lifecycle work.
bootstrap_update_target="${TMP_DIR}/bootstrap-update-target"
expect_status 0 "${TMP_DIR}/bootstrap-update-initial.out" \
  bash "${SETUP_SCRIPT}" --non-interactive --profile minimal --skip-check "${bootstrap_update_target}" </dev/null
bootstrap_source="${TMP_DIR}/bootstrap-failing-source"
mkdir -p "${bootstrap_source}"
cp -pR "${REPO_ROOT}/." "${bootstrap_source}/"
cat >"${bootstrap_source}/.beryl/agent/scripts/bootstrap-agent-context.sh" <<'BOOTSTRAP'
#!/usr/bin/env bash
set -euo pipefail
[[ -f .beryl/lock.json ]] || {
  printf 'bootstrap observed no committed lock\n' >&2
  exit 71
}
printf 'bootstrap observed committed lock\n' >&2
exit 72
BOOTSTRAP
chmod +x "${bootstrap_source}/.beryl/agent/scripts/bootstrap-agent-context.sh"
expect_status 2 "${TMP_DIR}/bootstrap-update.out" \
  bash "${bootstrap_source}/.beryl/scripts/setup-project.sh" --non-interactive --bootstrap \
  --skip-check "${bootstrap_update_target}" </dev/null
assert_contains "${TMP_DIR}/bootstrap-update.out" 'bootstrap observed committed lock'
assert_contains "${TMP_DIR}/bootstrap-update.out" 'lifecycle is committed; standalone bootstrap failed exit=2'
assert_contains "${TMP_DIR}/bootstrap-update.out" 'setup follow-up failed, but the lifecycle remains committed'
[[ -f "${bootstrap_update_target}/.beryl/lock.json" ]] || \
  fail 'bootstrap failure removed the committed update lock'
cmp -s "${bootstrap_source}/.beryl/agent/scripts/bootstrap-agent-context.sh" \
  "${bootstrap_update_target}/.beryl/agent/scripts/bootstrap-agent-context.sh" || \
  fail 'bootstrap failure rolled back the committed update file surface'
expect_status 0 "${TMP_DIR}/bootstrap-update-followup.out" \
  sh "${bootstrap_source}/install.sh" --source-dir "${bootstrap_source}" --update \
  --target "${bootstrap_update_target}"

# The lower-level interactive installer no longer accepts a bootstrap choice
# inside its transaction. It gives the standalone follow-up instruction only
# after a lock was written.
interactive_installer_target="${TMP_DIR}/interactive-installer-target"
interactive_installer_input="${TMP_DIR}/interactive-installer-input"
interactive_installer_output="${TMP_DIR}/interactive-installer-output"
printf '1\n' >"${interactive_installer_input}"
: >"${interactive_installer_output}"
expect_status 0 "${TMP_DIR}/interactive-installer.out" \
  env BERYL_INSTALL_PROMPT_INPUT="${interactive_installer_input}" \
  BERYL_INSTALL_PROMPT_OUTPUT="${interactive_installer_output}" \
  sh "${REPO_ROOT}/install.sh" --interactive --source-dir "${REPO_ROOT}" \
  --target "${interactive_installer_target}"
[[ -f "${interactive_installer_target}/.beryl/lock.json" ]] || \
  fail 'interactive installer did not commit its lock before post-action guidance'
assert_contains "${TMP_DIR}/interactive-installer.out" \
  'agent bootstrap is a standalone post-transaction action'
assert_contains "${TMP_DIR}/interactive-installer.out" \
  "--bootstrap-agent --target ${interactive_installer_target}"
[[ ! -e "${interactive_installer_target}/.beryl/agent/bootstrap-status.json" ]] || \
  fail 'interactive installer ran bootstrap inside the lifecycle transaction'

# Adapter configuration is a post-commit setup concern, so it retains an
# exact backup until the requested follow-up check succeeds. A failed check
# returns the qualified exit status and restores the target-owned adapter.
adapter_check_target="${TMP_DIR}/adapter-check-target"
expect_status 2 "${TMP_DIR}/adapter-check.out" \
  bash "${failing_source}/.beryl/scripts/setup-project.sh" --non-interactive --profile standard \
  --stack generic --test-runner custom --related-test-cmd '(printf related)' \
  --full-test-cmd '(printf full)' --run-check "${adapter_check_target}" </dev/null
assert_contains "${TMP_DIR}/adapter-check.out" 'restored affected-test adapter after follow-up failure'
cmp -s "${failing_source}/.beryl/agent/affected-tests.conf" \
  "${adapter_check_target}/.beryl/agent/affected-tests.conf" || \
  fail 'failed follow-up check did not restore affected-test adapter configuration'

printf 'setup lifecycle tests passed\n'
