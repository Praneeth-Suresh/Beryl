#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-install-security.XXXXXX")"
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

snapshot_tree() {
  local source="$1"
  local output="$2"
  tar -cf "${output}" -C "${source}" .
}

assert_tree_unchanged() {
  local source="$1"
  local before="$2"
  local after="${before}.after"
  snapshot_tree "${source}" "${after}"
  cmp -s "${before}" "${after}" || fail "target changed after rejected or failed install: ${source}"
}

run_local_install() {
  sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" "$@"
}

# Existing control-plane locations are never followed.  This is intentionally
# a first-install fixture: an unlocked .beryl symlink must be rejected before
# staging is applied to the target.
parent_link_target="${TMP_DIR}/parent-link-target"
external_control_plane="${TMP_DIR}/external-control-plane"
mkdir -p "${parent_link_target}" "${external_control_plane}"
printf 'external .beryl sentinel\n' >"${external_control_plane}/sentinel.txt"
ln -s "${external_control_plane}" "${parent_link_target}/.beryl"
expect_failure "${TMP_DIR}/parent-link.out" run_local_install --target "${parent_link_target}" --profile minimal
assert_contains "${TMP_DIR}/parent-link.out" 'existing unlocked .beryl directory refused'
[[ "$(<"${external_control_plane}/sentinel.txt")" == 'external .beryl sentinel' ]] || \
  fail 'parent .beryl symlink changed its external referent'

# A lexical target whose *ancestor* is a symlink is unsafe even when the
# target leaf itself exists and is a normal directory.
target_ancestor_parent="${TMP_DIR}/target-ancestor-parent"
target_ancestor_external="${TMP_DIR}/target-ancestor-external"
mkdir -p "${target_ancestor_parent}" "${target_ancestor_external}/existing-target"
printf 'external target sentinel\n' >"${target_ancestor_external}/existing-target/sentinel.txt"
ln -s "${target_ancestor_external}" "${target_ancestor_parent}/linked-parent"
expect_failure "${TMP_DIR}/target-ancestor.out" run_local_install \
  --target "${target_ancestor_parent}/linked-parent/existing-target" --profile minimal
assert_contains "${TMP_DIR}/target-ancestor.out" 'target or ancestor is a symlink'
[[ "$(<"${target_ancestor_external}/existing-target/sentinel.txt")" == 'external target sentinel' ]] || \
  fail 'target ancestor symlink changed its external referent'

# Even an explicit overwrite policy may not follow a root-shim symlink.
leaf_link_target="${TMP_DIR}/leaf-link-target"
external_shim="${TMP_DIR}/external-agents.md"
mkdir -p "${leaf_link_target}"
printf 'external AGENTS sentinel\n' >"${external_shim}"
ln -s "${external_shim}" "${leaf_link_target}/AGENTS.md"
expect_failure "${TMP_DIR}/leaf-link.out" run_local_install --target "${leaf_link_target}" --profile minimal --root-conflict overwrite
assert_contains "${TMP_DIR}/leaf-link.out" 'unsafe initial-install destination'
[[ "$(<"${external_shim}")" == 'external AGENTS sentinel' ]] || \
  fail 'AGENTS.md symlink changed its external referent'
[[ ! -e "${leaf_link_target}/.beryl" ]] || fail 'AGENTS.md symlink rejection created a control plane'

# Root conflicts and missing prerequisites are preflight checks: no target
# state may be changed when they fail.
root_conflict_target="${TMP_DIR}/root-conflict-target"
mkdir -p "${root_conflict_target}"
printf 'target-owned AGENTS contract\n' >"${root_conflict_target}/AGENTS.md"
snapshot_tree "${root_conflict_target}" "${TMP_DIR}/root-conflict-before.tar"
expect_failure "${TMP_DIR}/root-conflict.out" run_local_install --target "${root_conflict_target}" --profile minimal
assert_contains "${TMP_DIR}/root-conflict.out" 'root file conflict: AGENTS.md'
assert_tree_unchanged "${root_conflict_target}" "${TMP_DIR}/root-conflict-before.tar"

missing_runtime_target="${TMP_DIR}/missing-runtime-target"
runtime_bin="${TMP_DIR}/runtime-bin"
mkdir -p "${runtime_bin}"
ln -s "$(command -v basename)" "${runtime_bin}/basename"
ln -s "$(command -v dirname)" "${runtime_bin}/dirname"
expect_failure "${TMP_DIR}/missing-runtime.out" env PATH="${runtime_bin}" /bin/sh "${REPO_ROOT}/install.sh" \
  --source-dir "${REPO_ROOT}" --target "${missing_runtime_target}" --profile minimal
assert_contains "${TMP_DIR}/missing-runtime.out" 'required runtime missing: bash'
[[ ! -e "${missing_runtime_target}" ]] || fail 'missing runtime validation created the target'

# A post-apply hook failure rolls an existing target back to its exact
# pre-install archive, including removal of transaction-created directories.
failing_source="${TMP_DIR}/failing-source"
hook_failure_target="${TMP_DIR}/hook-failure-target"
mkdir -p "${failing_source}" "${hook_failure_target}"
cp -pR "${REPO_ROOT}/." "${failing_source}/"
printf '#!/usr/bin/env bash\nprintf ".beryl/agent/session-state.md\\n" >> .gitignore\nexit 91\n' \
  >"${failing_source}/.beryl/agent/scripts/seed-agent-context.sh"
chmod +x "${failing_source}/.beryl/agent/scripts/seed-agent-context.sh"
printf 'target-owned README\n' >"${hook_failure_target}/README.md"
snapshot_tree "${hook_failure_target}" "${TMP_DIR}/hook-failure-before.tar"
expect_failure "${TMP_DIR}/hook-failure.out" sh "${REPO_ROOT}/install.sh" --source-dir "${failing_source}" \
  --target "${hook_failure_target}" --profile minimal
assert_contains "${TMP_DIR}/hook-failure.out" 'beryl: install failed phase=hook'
assert_tree_unchanged "${hook_failure_target}" "${TMP_DIR}/hook-failure-before.tar"

# The standalone shim synchronizer is a root-contract write boundary too. It
# must reject both leaf and parent symlinks before producing any shim marker or
# changing an external referent.
prepare_sync_fixture() {
  local target="$1"
  mkdir -p "${target}/.beryl/agent/scripts"
  cp "${REPO_ROOT}/.beryl/agent/scripts/sync-agent-env.sh" \
    "${target}/.beryl/agent/scripts/sync-agent-env.sh"
  cp "${REPO_ROOT}/.beryl/agent/tool-instruction-template.md" \
    "${target}/.beryl/agent/tool-instruction-template.md"
  chmod +x "${target}/.beryl/agent/scripts/sync-agent-env.sh"
}

sync_leaf_target="${TMP_DIR}/sync-leaf-target"
sync_leaf_external="${TMP_DIR}/sync-leaf-external.md"
prepare_sync_fixture "${sync_leaf_target}"
printf 'external leaf sentinel\n' >"${sync_leaf_external}"
ln -s "${sync_leaf_external}" "${sync_leaf_target}/AGENTS.md"
expect_failure "${TMP_DIR}/sync-leaf.out" \
  bash "${sync_leaf_target}/.beryl/agent/scripts/sync-agent-env.sh"
assert_contains "${TMP_DIR}/sync-leaf.out" 'symlink is not allowed'
[[ "$(<"${sync_leaf_external}")" == 'external leaf sentinel' ]] || \
  fail 'standalone shim sync changed an external leaf referent'
[[ ! -e "${sync_leaf_target}/.cursor" ]] || fail 'standalone shim sync wrote a marker before leaf rejection'

sync_parent_target="${TMP_DIR}/sync-parent-target"
sync_parent_external="${TMP_DIR}/sync-parent-external"
prepare_sync_fixture "${sync_parent_target}"
mkdir -p "${sync_parent_external}"
printf 'external parent sentinel\n' >"${sync_parent_external}/sentinel.txt"
ln -s "${sync_parent_external}" "${sync_parent_target}/.cursor"
expect_failure "${TMP_DIR}/sync-parent.out" \
  bash "${sync_parent_target}/.beryl/agent/scripts/sync-agent-env.sh"
assert_contains "${TMP_DIR}/sync-parent.out" 'symlink is not allowed'
[[ "$(<"${sync_parent_external}/sentinel.txt")" == 'external parent sentinel' ]] || \
  fail 'standalone shim sync changed an external parent referent'
[[ ! -e "${sync_parent_target}/AGENTS.md" ]] || fail 'standalone shim sync wrote a marker before parent rejection'

# Bootstrap agents are arbitrary host integrations.  They are a separate
# action against a completed lock, so failure has its own exit code and cannot
# change a normal install/update outcome.
# The transactional hook runner must never call bootstrap: arbitrary agent
# effects are not rollback-safe and are authorized only by --bootstrap-agent.
if sed -n '/^run_post_install_hooks()/,/^}/p' "${REPO_ROOT}/install.sh" | \
  grep -Fq 'bootstrap-agent-context)'; then
  fail 'transactional post-install hooks still dispatch bootstrap-agent-context'
fi
bootstrap_target="${TMP_DIR}/bootstrap-target"
run_local_install --target "${bootstrap_target}" --profile minimal
printf '#!/usr/bin/env bash\nexit 92\n' >"${bootstrap_target}/.beryl/agent/scripts/bootstrap-agent-context.sh"
chmod +x "${bootstrap_target}/.beryl/agent/scripts/bootstrap-agent-context.sh"
if sh "${REPO_ROOT}/install.sh" --bootstrap-agent --target "${bootstrap_target}" \
  >"${TMP_DIR}/bootstrap-failure.out" 2>&1; then
  fail 'dedicated bootstrap failure unexpectedly succeeded'
else
  bootstrap_exit=$?
fi
[[ "${bootstrap_exit}" -eq 2 ]] || fail "bootstrap failure exit was ${bootstrap_exit}, expected 2"
assert_contains "${TMP_DIR}/bootstrap-failure.out" 'agent bootstrap failed exit=92; installation remains committed'
[[ -f "${bootstrap_target}/.beryl/lock.json" ]] || fail 'bootstrap failure changed the committed lockfile'
run_local_install --update --source-dir "${REPO_ROOT}" --target "${bootstrap_target}" --profile minimal

# The standalone bootstrap entry point must not follow a target-controlled
# script symlink out of the locked control plane.
bootstrap_external="${TMP_DIR}/bootstrap-external"
mkdir -p "${bootstrap_external}"
printf '#!/usr/bin/env bash\nprintf "external bootstrap ran" >"%s/marker"\n' "${bootstrap_external}" \
  >"${bootstrap_external}/bootstrap-agent-context.sh"
chmod +x "${bootstrap_external}/bootstrap-agent-context.sh"
rm "${bootstrap_target}/.beryl/agent/scripts/bootstrap-agent-context.sh"
ln -s "${bootstrap_external}/bootstrap-agent-context.sh" \
  "${bootstrap_target}/.beryl/agent/scripts/bootstrap-agent-context.sh"
expect_failure "${TMP_DIR}/bootstrap-script-symlink.out" \
  sh "${REPO_ROOT}/install.sh" --bootstrap-agent --target "${bootstrap_target}"
assert_contains "${TMP_DIR}/bootstrap-script-symlink.out" 'bootstrap target bootstrap script must not be a symlink'
[[ ! -e "${bootstrap_external}/marker" ]] || fail 'standalone bootstrap followed an external script symlink'

standalone_bootstrap_target="${TMP_DIR}/standalone-bootstrap-target"
expect_failure "${TMP_DIR}/bootstrap-selector.out" run_local_install --bootstrap-agent \
  --source-dir "${REPO_ROOT}" --target "${standalone_bootstrap_target}"
assert_contains "${TMP_DIR}/bootstrap-selector.out" '--bootstrap-agent is a standalone action'
[[ ! -e "${standalone_bootstrap_target}" ]] || fail 'bootstrap selector rejection created a target'

# agent-bootstrap is a standalone action selector, never a lifecycle
# component. The same rejection applies to locked updates before staging,
# backup, hook, or lock mutation.
bootstrap_component_update_target="${TMP_DIR}/bootstrap-component-update-target"
run_local_install --target "${bootstrap_component_update_target}" --profile minimal
snapshot_tree "${bootstrap_component_update_target}" "${TMP_DIR}/bootstrap-component-update-before.tar"
expect_failure "${TMP_DIR}/bootstrap-component-update.out" run_local_install --update \
  --target "${bootstrap_component_update_target}" --components agent-bootstrap
assert_contains "${TMP_DIR}/bootstrap-component-update.out" \
  'agent-bootstrap is not an installable component; run --bootstrap-agent against a locked target'
assert_tree_unchanged "${bootstrap_component_update_target}" \
  "${TMP_DIR}/bootstrap-component-update-before.tar"

# Parse and source errors must not create an absent target, and an unlocked
# control plane is never adopted implicitly.
invalid_target="${TMP_DIR}/invalid-target"
expect_failure "${TMP_DIR}/invalid-args.out" run_local_install --target "${invalid_target}" --root-conflict invalid
assert_contains "${TMP_DIR}/invalid-args.out" '--root-conflict must be fail, overwrite, or skip'
[[ ! -e "${invalid_target}" ]] || fail 'invalid arguments created the target'

unlocked_target="${TMP_DIR}/unlocked-target"
mkdir -p "${unlocked_target}/.beryl"
printf 'target-owned Beryl-like file\n' >"${unlocked_target}/.beryl/custom.txt"
snapshot_tree "${unlocked_target}" "${TMP_DIR}/unlocked-before.tar"
expect_failure "${TMP_DIR}/unlocked.out" run_local_install --target "${unlocked_target}" --profile minimal
assert_contains "${TMP_DIR}/unlocked.out" 'existing unlocked .beryl directory refused'
assert_tree_unchanged "${unlocked_target}" "${TMP_DIR}/unlocked-before.tar"

# Each parallel transaction must use its own private temporary stage/rollback
# directory; predictable PID-only staging risks cross-target contamination.
parallel_pids=""
for parallel_index in 1 2 3 4; do
  parallel_target="${TMP_DIR}/parallel-${parallel_index}"
  (run_local_install --target "${parallel_target}" --profile minimal >"${TMP_DIR}/parallel-${parallel_index}.out" 2>&1) &
  parallel_pids="${parallel_pids} $!"
done
for parallel_pid in ${parallel_pids}; do
  wait "${parallel_pid}" || fail 'parallel install failed'
done
for parallel_index in 1 2 3 4; do
  [[ -f "${TMP_DIR}/parallel-${parallel_index}/.beryl/lock.json" ]] || fail 'parallel install lock missing'
  [[ -f "${TMP_DIR}/parallel-${parallel_index}/AGENTS.md" ]] || fail 'parallel install shim missing'
done
parallel_pids=""
for parallel_index in 1 2 3 4; do
  parallel_target="${TMP_DIR}/parallel-${parallel_index}"
  (run_local_install --update --target "${parallel_target}" --profile minimal >"${TMP_DIR}/parallel-update-${parallel_index}.out" 2>&1) &
  parallel_pids="${parallel_pids} $!"
done
for parallel_pid in ${parallel_pids}; do
  wait "${parallel_pid}" || fail 'parallel lock update failed'
done
for parallel_index in 1 2 3 4; do
  [[ -f "${TMP_DIR}/parallel-${parallel_index}/.beryl/lock.json" ]] || fail 'parallel update lock missing'
done

# Candidate lock names must be unguessable and target-sibling. A pre-created
# former PID name is hostile state, not an installer output path.
lock_collision_target="${TMP_DIR}/lock-collision-target"
lock_collision_external="${TMP_DIR}/lock-collision-external"
run_local_install --target "${lock_collision_target}" --profile minimal
printf 'lock collision sentinel\n' >"${lock_collision_external}"
ln -s "${lock_collision_external}" "${lock_collision_target}/.beryl/.lock.json.$$"
run_local_install --update --target "${lock_collision_target}" --profile minimal \
  >"${TMP_DIR}/lock-collision-update.out" 2>&1
[[ "$(<"${lock_collision_external}")" == 'lock collision sentinel' ]] || \
  fail 'update followed predictable lock candidate'
! grep -Fq '.lock.json.$$' "${REPO_ROOT}/install.sh" || \
  fail 'installer still contains a predictable PID lock candidate'

# Update backups used to derive their directory from date plus the shell PID.
# A target-owned symlink at that former name must neither be followed nor
# mutate its external referent. The wrapper exec preserves its PID into the
# installer while a test-local date command makes the old name deterministic.
backup_collision_target="${TMP_DIR}/backup-collision-target"
backup_collision_external="${TMP_DIR}/backup-collision-external"
backup_collision_bin="${TMP_DIR}/backup-collision-bin"
backup_collision_wrapper="${TMP_DIR}/backup-collision-wrapper.sh"
run_local_install --target "${backup_collision_target}" --profile minimal
mkdir -p "${backup_collision_bin}" "${backup_collision_target}/.beryl/.updates"
printf '#!/bin/sh\nprintf "20000101T000000Z"\n' >"${backup_collision_bin}/date"
chmod +x "${backup_collision_bin}/date"
printf 'backup collision sentinel\n' >"${backup_collision_external}"
cat >"${backup_collision_wrapper}" <<'WRAPPER'
#!/bin/sh
target="$1"
external="$2"
fake_bin="$3"
repo="$4"
ln -s "$external" "$target/.beryl/.updates/20000101T000000Z-$$"
exec env PATH="$fake_bin:$PATH" sh "$repo/install.sh" --update --source-dir "$repo" --target "$target" --profile minimal
WRAPPER
chmod +x "${backup_collision_wrapper}"
"${backup_collision_wrapper}" "${backup_collision_target}" "${backup_collision_external}" \
  "${backup_collision_bin}" "${REPO_ROOT}" >"${TMP_DIR}/backup-collision.out" 2>&1
[[ "$(<"${backup_collision_external}")" == 'backup collision sentinel' ]] || \
  fail 'update followed a former predictable backup candidate'
! grep -Eq 'backup_stamp=.*\$\$' "${REPO_ROOT}/install.sh" || \
  fail 'installer still contains a predictable PID backup candidate'

# A managed symlink is hostile state during update. It must be refused before
# snapshot/apply rather than replaced, leaving both target and referent intact.
managed_leaf_target="${TMP_DIR}/managed-leaf-target"
managed_leaf_external="${TMP_DIR}/managed-leaf-external"
run_local_install --target "${managed_leaf_target}" --profile minimal
printf 'managed leaf sentinel\n' >"${managed_leaf_external}"
rm "${managed_leaf_target}/AGENTS.md"
ln -s "${managed_leaf_external}" "${managed_leaf_target}/AGENTS.md"
snapshot_tree "${managed_leaf_target}" "${TMP_DIR}/managed-leaf-before.tar"
expect_failure "${TMP_DIR}/managed-leaf.out" run_local_install --update \
  --target "${managed_leaf_target}" --profile minimal
assert_contains "${TMP_DIR}/managed-leaf.out" 'leaf-symlink'
assert_tree_unchanged "${managed_leaf_target}" "${TMP_DIR}/managed-leaf-before.tar"
[[ "$(<"${managed_leaf_external}")" == 'managed leaf sentinel' ]] || \
  fail 'update changed managed leaf symlink referent'

# The lock is state read by every update. A symlinked lock must fail before
# parsing it or changing the target.
symlink_lock_target="${TMP_DIR}/symlink-lock-target"
symlink_lock_external="${TMP_DIR}/symlink-lock-external"
run_local_install --target "${symlink_lock_target}" --profile minimal
mv "${symlink_lock_target}/.beryl/lock.json" "${TMP_DIR}/real-lock.json"
printf 'external lock sentinel\n' >"${symlink_lock_external}"
ln -s "${symlink_lock_external}" "${symlink_lock_target}/.beryl/lock.json"
snapshot_tree "${symlink_lock_target}" "${TMP_DIR}/symlink-lock-before.tar"
expect_failure "${TMP_DIR}/symlink-lock.out" run_local_install --update \
  --target "${symlink_lock_target}" --profile minimal
assert_contains "${TMP_DIR}/symlink-lock.out" 'leaf-symlink'
assert_tree_unchanged "${symlink_lock_target}" "${TMP_DIR}/symlink-lock-before.tar"
[[ "$(<"${symlink_lock_external}")" == 'external lock sentinel' ]] || \
  fail 'update read or changed symlinked lock referent'

# The containing .beryl directory is equally hostile when symlinked. Refuse it
# before any lock parsing and leave the external control-plane untouched.
symlink_lock_parent_target="${TMP_DIR}/symlink-lock-parent-target"
symlink_lock_parent_external="${TMP_DIR}/symlink-lock-parent-external"
run_local_install --target "${symlink_lock_parent_target}" --profile minimal
mv "${symlink_lock_parent_target}/.beryl" "${TMP_DIR}/real-beryl"
mkdir -p "${symlink_lock_parent_external}"
printf 'external lock parent sentinel\n' >"${symlink_lock_parent_external}/sentinel.txt"
ln -s "${symlink_lock_parent_external}" "${symlink_lock_parent_target}/.beryl"
snapshot_tree "${symlink_lock_parent_target}" "${TMP_DIR}/symlink-lock-parent-before.tar"
expect_failure "${TMP_DIR}/symlink-lock-parent.out" run_local_install --update \
  --target "${symlink_lock_parent_target}" --profile minimal
assert_contains "${TMP_DIR}/symlink-lock-parent.out" 'parent-symlink'
assert_tree_unchanged "${symlink_lock_parent_target}" "${TMP_DIR}/symlink-lock-parent-before.tar"
[[ "$(<"${symlink_lock_parent_external}/sentinel.txt")" == 'external lock parent sentinel' ]] || \
  fail 'update read or changed symlinked lock parent referent'

# A held target-local lifecycle lock rejects a second same-target operation
# without a target mutation. Different-target parallel coverage above remains
# the proof that this exclusion is scoped to one target only.
same_target="${TMP_DIR}/same-target-lifecycle"
run_local_install --target "${same_target}" --profile minimal
same_target_gate="${TMP_DIR}/same-target-success.gate"
: >"${same_target_gate}"
(BERYL_LIFECYCLE_TEST_HOLD_LOCK_FILE="${same_target_gate}" run_local_install --update \
  --target "${same_target}" --profile minimal >"${TMP_DIR}/same-target-first.out" 2>&1) &
same_target_pid=$!
for _ in $(seq 1 60); do
  [[ -d "${same_target}/.beryl.lifecycle.lock" ]] && break
  sleep 0.05
done
[[ -d "${same_target}/.beryl.lifecycle.lock" ]] || fail 'first lifecycle operation did not acquire target lock'
snapshot_tree "${same_target}" "${TMP_DIR}/same-target-before.tar"
expect_failure "${TMP_DIR}/same-target-second.out" run_local_install --update \
  --target "${same_target}" --profile minimal
assert_contains "${TMP_DIR}/same-target-second.out" 'another Beryl lifecycle operation is already running'
snapshot_tree "${same_target}" "${TMP_DIR}/same-target-after-second.tar"
cmp -s "${TMP_DIR}/same-target-before.tar" "${TMP_DIR}/same-target-after-second.tar" || \
  fail 'second same-target lifecycle changed the target while the first held the lock'
rm "${same_target_gate}"
wait "${same_target_pid}" || fail 'held lifecycle operation failed'
[[ ! -e "${same_target}/.beryl.lifecycle.lock" ]] || fail 'lifecycle lock was not removed after success'
[[ -f "${same_target}/.beryl/lock.json" ]] || fail 'same-target lifecycle left no coherent lock'

# The exclusion also spans rollback. While a lock-holding update is forced to
# fail after mutation begins, another lifecycle still refuses; the first one
# then restores the exact prior target and releases its lock.
snapshot_tree "${same_target}" "${TMP_DIR}/same-target-rollback-before.tar"
same_target_rollback_gate="${TMP_DIR}/same-target-rollback.gate"
: >"${same_target_rollback_gate}"
(BERYL_LIFECYCLE_TEST_HOLD_LOCK_FILE="${same_target_rollback_gate}" BERYL_UPDATE_FAIL_AT='apply:AGENTS.md' \
  run_local_install --update --target "${same_target}" --profile minimal \
  >"${TMP_DIR}/same-target-rollback-first.out" 2>&1) &
same_target_rollback_pid=$!
for _ in $(seq 1 60); do
  [[ -d "${same_target}/.beryl.lifecycle.lock" ]] && break
  sleep 0.05
done
[[ -d "${same_target}/.beryl.lifecycle.lock" ]] || fail 'failing lifecycle operation did not acquire target lock'
expect_failure "${TMP_DIR}/same-target-rollback-second.out" run_local_install --update \
  --target "${same_target}" --profile minimal
assert_contains "${TMP_DIR}/same-target-rollback-second.out" 'another Beryl lifecycle operation is already running'
rm "${same_target_rollback_gate}"
if wait "${same_target_rollback_pid}"; then
  fail 'forced lifecycle rollback unexpectedly succeeded'
fi
assert_contains "${TMP_DIR}/same-target-rollback-first.out" 'reason=forced rollback=ok'
snapshot_tree "${same_target}" "${TMP_DIR}/same-target-rollback-after.tar"
cmp -s "${TMP_DIR}/same-target-rollback-before.tar" "${TMP_DIR}/same-target-rollback-after.tar" || \
  fail 'forced same-target lifecycle did not restore the exact pre-update target'
[[ ! -e "${same_target}/.beryl.lifecycle.lock" ]] || fail 'lifecycle lock was not removed after rollback'
[[ -f "${same_target}/.beryl/lock.json" ]] || fail 'failed same-target lifecycle left no coherent lock'

printf 'install security tests passed\n'
