#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-recovery.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

expect_failure() {
  local output="$1"
  shift
  if "$@" >"${output}" 2>&1; then fail "command unexpectedly succeeded: $*"; fi
}

assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 did not contain: $2"; }

snapshot_tree() { tar -cf "$2" -C "$1" .; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

assert_tree_unchanged() {
  tar -cf "$2.after" -C "$1" .
  cmp -s "$2" "$2.after" || fail "target changed after refusal: $1"
}

run_install() { sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" "$@"; }

create_candidate_checkout() {
  local destination="$1"
  local rel source destination_file

  git clone -q "${REPO_ROOT}" "${destination}"
  while IFS= read -r -d '' rel; do
    source="${REPO_ROOT}/${rel}"
    destination_file="${destination}/${rel}"
    [[ ! -L "${source}" ]] || fail "candidate fixture source must not contain symlinks: ${rel}"
    [[ -f "${source}" ]] || fail "candidate fixture tracked source is missing or unsupported: ${rel}"
    mkdir -p "$(dirname "${destination_file}")"
    cp -p "${source}" "${destination_file}"
  done < <(git -C "${REPO_ROOT}" ls-files -z)
  git -C "${destination}" add -u
}

make_git_target() {
  local target="$1"
  mkdir -p "${target}"
  git -C "${target}" init -q
  git -C "${target}" config core.hooksPath legacy-hooks
}

# Uninstall has an ownership proof, so target-owned files remain while hook
# integration returns to its original local Git configuration.
uninstall_target="${TMP_DIR}/uninstall-target"
make_git_target "${uninstall_target}"
run_install --target "${uninstall_target}" --profile standard --enable-githooks --hook-conflict replace
printf 'target-owned content\n' >"${uninstall_target}/.beryl/user-owned.txt"
sh "${REPO_ROOT}/install.sh" --uninstall --profile standard --source-dir "${REPO_ROOT}" --target "${uninstall_target}" >"${TMP_DIR}/uninstall.out"
[[ ! -e "${uninstall_target}/.beryl/lock.json" ]] || fail 'uninstall left lockfile'
[[ ! -e "${uninstall_target}/.beryl/agent/scripts/agent-doctor.sh" ]] || fail 'uninstall left managed file'
[[ "$(<"${uninstall_target}/.beryl/user-owned.txt")" == 'target-owned content' ]] || fail 'uninstall removed unknown file'
[[ "$(git -C "${uninstall_target}" config --local --get core.hooksPath)" == legacy-hooks ]] || fail 'uninstall did not restore prior hooks path'

# A legacy/local lock cannot silently become a remote recovery fetch. The
# trust refusal occurs before any curl invocation or target mutation.
remote_refusal_target="${TMP_DIR}/remote-refusal-target"
run_install --target "${remote_refusal_target}" --profile minimal
remote_refusal_bin="${TMP_DIR}/remote-refusal-bin"
mkdir -p "${remote_refusal_bin}"
printf '#!/bin/sh\nprintf "curl invoked unexpectedly\\n" >&2\nexit 99\n' >"${remote_refusal_bin}/curl"
chmod +x "${remote_refusal_bin}/curl"
expect_failure "${TMP_DIR}/remote-refusal.out" env PATH="${remote_refusal_bin}:${PATH}" \
  sh "${REPO_ROOT}/install.sh" --uninstall --profile minimal --target "${remote_refusal_target}"
assert_contains "${TMP_DIR}/remote-refusal.out" 'remote lifecycle requires --ref'
! grep -Fq 'curl invoked unexpectedly' "${TMP_DIR}/remote-refusal.out" || fail 'remote uninstall invoked curl before trust refusal'
[[ -f "${remote_refusal_target}/.beryl/lock.json" ]] || fail 'remote uninstall refusal mutated target'

# Preserve-mode never owned core.hooksPath, so uninstall leaves a target-owned
# hook manager unchanged while still removing Beryl's files.
preserve_target="${TMP_DIR}/preserve-target"
make_git_target "${preserve_target}"
run_install --target "${preserve_target}" --profile standard --enable-githooks --hook-conflict preserve
sh "${REPO_ROOT}/install.sh" --uninstall --profile standard --source-dir "${REPO_ROOT}" --target "${preserve_target}" >"${TMP_DIR}/preserve-uninstall.out"
[[ "$(git -C "${preserve_target}" config --local --get core.hooksPath)" == legacy-hooks ]] || fail 'preserve-mode uninstall changed user hooks'

# Replace-mode becomes unsafe if a user later changes hooks; refuse before
# deleting files rather than overwriting the new choice during cleanup.
changed_hook_target="${TMP_DIR}/changed-hook-target"
make_git_target "${changed_hook_target}"
run_install --target "${changed_hook_target}" --profile standard --enable-githooks --hook-conflict replace
git -C "${changed_hook_target}" config core.hooksPath user-changed-hooks
snapshot_tree "${changed_hook_target}" "${TMP_DIR}/changed-hook-before.tar"
expect_failure "${TMP_DIR}/changed-hook.out" sh "${REPO_ROOT}/install.sh" --uninstall --profile standard --source-dir "${REPO_ROOT}" --target "${changed_hook_target}"
assert_contains "${TMP_DIR}/changed-hook.out" 'core.hooksPath was changed by the user'
assert_tree_unchanged "${changed_hook_target}" "${TMP_DIR}/changed-hook-before.tar"

# A changed managed file blocks uninstall before any deletion, even when an
# adjacent unknown file makes broad directory removal tempting.
changed_target="${TMP_DIR}/changed-target"
run_install --target "${changed_target}" --profile minimal
printf 'local modification\n' >>"${changed_target}/.beryl/agent/README.md"
printf 'unknown survives\n' >"${changed_target}/.beryl/unknown.txt"
snapshot_tree "${changed_target}" "${TMP_DIR}/changed-before.tar"
expect_failure "${TMP_DIR}/changed.out" sh "${REPO_ROOT}/install.sh" --uninstall --profile minimal --source-dir "${REPO_ROOT}" --target "${changed_target}"
assert_contains "${TMP_DIR}/changed.out" 'managed file changed'
assert_tree_unchanged "${changed_target}" "${TMP_DIR}/changed-before.tar"

# A lockfile and destination symlink are both untrusted recovery inputs.
malicious_target="${TMP_DIR}/malicious-target"
run_install --target "${malicious_target}" --profile minimal
malicious_lock="${malicious_target}/.beryl/lock.json"
printf 'do not delete\n' >"${malicious_target}/.beryl/user-owned.txt"
printf 'target-owned ignore\n' >"${malicious_target}/.gitignore"
user_digest="$(sha256_of "${malicious_target}/.beryl/user-owned.txt")"
ignore_digest="$(sha256_of "${malicious_target}/.gitignore")"
sed \
  -e 's/"managedPaths": \[/"managedPaths": [".gitignore",".beryl\/user-owned.txt",/' \
  -e "s/\"managedPathDigests\": \[/\"managedPathDigests\": [\".gitignore:${ignore_digest}\",\".beryl\\/user-owned.txt:${user_digest}\",/" \
  "${malicious_lock}" >"${malicious_lock}.next"
mv "${malicious_lock}.next" "${malicious_lock}"
snapshot_tree "${malicious_target}" "${TMP_DIR}/malicious-before.tar"
expect_failure "${TMP_DIR}/malicious.out" sh "${REPO_ROOT}/install.sh" --uninstall --profile minimal --source-dir "${REPO_ROOT}" --target "${malicious_target}"
assert_contains "${TMP_DIR}/malicious.out" 'managed path is outside selected surface: .gitignore'
assert_tree_unchanged "${malicious_target}" "${TMP_DIR}/malicious-before.tar"

symlink_target="${TMP_DIR}/symlink-target"
symlink_external="${TMP_DIR}/symlink-external.md"
run_install --target "${symlink_target}" --profile minimal
rm "${symlink_target}/.beryl/agent/README.md"
printf 'external\n' >"${symlink_external}"
ln -s "${symlink_external}" "${symlink_target}/.beryl/agent/README.md"
expect_failure "${TMP_DIR}/symlink.out" sh "${REPO_ROOT}/install.sh" --uninstall --profile minimal --source-dir "${REPO_ROOT}" --target "${symlink_target}"
assert_contains "${TMP_DIR}/symlink.out" 'unsafe recovery destination'
[[ "$(<"${symlink_external}")" == external ]] || fail 'recovery followed managed symlink'

# An update records an immutable snapshot. Restore applies it transactionally,
# brings back the prior lock and content, and restores the captured hook state.
update_source="${TMP_DIR}/update-source"
create_candidate_checkout "${update_source}"
printf '\nrecovery update marker\n' >>"${update_source}/.beryl/agent/README.md"
printf '#!/bin/sh\nprintf "recovery update file\\n"\n' >"${update_source}/.beryl/agent/scripts/recovery-added.sh"
chmod +x "${update_source}/.beryl/agent/scripts/recovery-added.sh"
git -C "${update_source}" add .beryl/agent/README.md .beryl/agent/scripts/recovery-added.sh
git -C "${update_source}" -c user.email=tests@example.invalid -c user.name='Beryl tests' commit -qm 'recovery update fixture'
restore_target="${TMP_DIR}/restore-target"
make_git_target "${restore_target}"
run_install --target "${restore_target}" --profile standard --enable-githooks --hook-conflict replace
cp "${restore_target}/.beryl/agent/README.md" "${TMP_DIR}/restore-readme-before.md"
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${restore_target}" --profile full >"${TMP_DIR}/update.out"
backup_id="$(sed -n 's/^beryl: update backup \.beryl\/\.updates\/\([^[:space:]]*\)$/\1/p' "${TMP_DIR}/update.out")"
[[ -n "${backup_id}" ]] || fail 'update did not report backup id'
printf 'unknown sibling survives\n' >"${restore_target}/.beryl/agent/scripts/user-owned-note.txt"
printf 'unknown driver sibling survives\n' >"${restore_target}/.beryl/driver/user-owned-note.txt"
[[ -f "${restore_target}/.beryl/driver/run.sh" ]] || fail 'full update did not add driver runtime'
git -C "${restore_target}" config core.hooksPath changed-after-update
snapshot_tree "${restore_target}" "${TMP_DIR}/restore-hook-changed-before.tar"
expect_failure "${TMP_DIR}/restore-hook-changed.out" env BERYL_RECOVERY_TEST_REQUIRE_TARGET_SIBLING=1 \
  sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile full --source-dir "${REPO_ROOT}" --current-source-dir "${update_source}" --target "${restore_target}"
assert_contains "${TMP_DIR}/restore-hook-changed.out" 'core.hooksPath was changed by the user'
assert_tree_unchanged "${restore_target}" "${TMP_DIR}/restore-hook-changed-before.tar"
git -C "${restore_target}" config core.hooksPath .beryl/githooks
restore_lock_collision_external="${TMP_DIR}/restore-lock-collision-external"
printf 'restore lock collision sentinel\n' >"${restore_lock_collision_external}"
# A former PID-named restore candidate must never be opened or replaced. The
# secure same-directory mktemp candidate leaves this hostile name untouched.
ln -s "${restore_lock_collision_external}" "${restore_target}/.beryl/.lock.restore.$$"
BERYL_RECOVERY_TEST_REQUIRE_TARGET_SIBLING=1 sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile full --source-dir "${REPO_ROOT}" --current-source-dir "${update_source}" --target "${restore_target}" >"${TMP_DIR}/restore.out"
[[ "$(<"${restore_lock_collision_external}")" == 'restore lock collision sentinel' ]] || fail 'restore followed predictable lock candidate'
cmp -s "${TMP_DIR}/restore-readme-before.md" "${restore_target}/.beryl/agent/README.md" || fail 'restore did not recover prior managed file'
[[ ! -e "${restore_target}/.beryl/agent/scripts/recovery-added.sh" ]] || fail 'restore left update-added managed file'
[[ "$(<"${restore_target}/.beryl/agent/scripts/user-owned-note.txt")" == 'unknown sibling survives' ]] || fail 'restore removed unknown sibling file'
[[ ! -e "${restore_target}/.beryl/driver/run.sh" ]] || fail 'restore left full-profile driver runtime'
[[ "$(<"${restore_target}/.beryl/driver/user-owned-note.txt")" == 'unknown driver sibling survives' ]] || fail 'restore removed unknown driver sibling file'
[[ "$(git -C "${restore_target}" config --local --get core.hooksPath)" == .beryl/githooks ]] || fail 'restore did not recover prior hook state'
assert_contains "${restore_target}/.beryl/lock.json" 'managedPathDigestsVersion'

# Backup metadata cannot smuggle a path or bytes into a restore. Every
# snapshot must remain represented, digest-proven, and release-authorized by
# its embedded historical lock before restore can begin changing the target.
backup_lock="${restore_target}/.beryl/.updates/${backup_id}/files/.beryl/lock.json"
backup_readme="${restore_target}/.beryl/.updates/${backup_id}/files/.beryl/agent/README.md"
cp "${backup_lock}" "${TMP_DIR}/backup-lock-original.json"
cp "${backup_readme}" "${TMP_DIR}/backup-readme-original.md"
backup_readme_digest="$(sha256_of "${backup_readme}")"
# The embedded backup lock is hostile state too: it must agree with the
# explicitly selected historical release before restore can copy it back.
sed 's/"components": \[/"components": ["driver",/' "${TMP_DIR}/backup-lock-original.json" >"${backup_lock}"
snapshot_tree "${restore_target}" "${TMP_DIR}/tampered-backup-components-before.tar"
expect_failure "${TMP_DIR}/tampered-backup-components.out" sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile standard --source-dir "${REPO_ROOT}" --current-source-dir "${REPO_ROOT}" --target "${restore_target}"
assert_contains "${TMP_DIR}/tampered-backup-components.out" 'invalid restored backup lockfile: resolved components do not match requested dependency closure'
assert_tree_unchanged "${restore_target}" "${TMP_DIR}/tampered-backup-components-before.tar"
sed 's/"requestedComponents": \[/"requestedComponents": ["driver",/' "${TMP_DIR}/backup-lock-original.json" >"${backup_lock}"
snapshot_tree "${restore_target}" "${TMP_DIR}/tampered-backup-requested-before.tar"
expect_failure "${TMP_DIR}/tampered-backup-requested.out" sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile standard --source-dir "${REPO_ROOT}" --current-source-dir "${REPO_ROOT}" --target "${restore_target}"
assert_contains "${TMP_DIR}/tampered-backup-requested.out" 'invalid restored backup lockfile: resolved components do not match requested dependency closure'
assert_tree_unchanged "${restore_target}" "${TMP_DIR}/tampered-backup-requested-before.tar"
cp "${TMP_DIR}/backup-lock-original.json" "${backup_lock}"
printf 'malicious backup bytes\n' >"${backup_readme}"
sed \
  -e 's#,".beryl/agent/README.md"##' \
  -e "s#,\".beryl/agent/README.md:${backup_readme_digest}\"##" \
  "${TMP_DIR}/backup-lock-original.json" >"${backup_lock}"
snapshot_tree "${restore_target}" "${TMP_DIR}/tampered-backup-lock-before.tar"
expect_failure "${TMP_DIR}/tampered-backup-lock.out" sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile standard --source-dir "${REPO_ROOT}" --current-source-dir "${REPO_ROOT}" --target "${restore_target}"
assert_contains "${TMP_DIR}/tampered-backup-lock.out" 'backup snapshot path is not owned by restored lock'
assert_tree_unchanged "${restore_target}" "${TMP_DIR}/tampered-backup-lock-before.tar"
cp "${TMP_DIR}/backup-lock-original.json" "${backup_lock}"
snapshot_tree "${restore_target}" "${TMP_DIR}/tampered-backup-bytes-before.tar"
expect_failure "${TMP_DIR}/tampered-backup-bytes.out" sh "${REPO_ROOT}/install.sh" --restore "${backup_id}" --profile standard --current-profile standard --source-dir "${REPO_ROOT}" --current-source-dir "${REPO_ROOT}" --target "${restore_target}"
assert_contains "${TMP_DIR}/tampered-backup-bytes.out" 'backup snapshot digest differs from restored lock'
assert_tree_unchanged "${restore_target}" "${TMP_DIR}/tampered-backup-bytes-before.tar"
cp "${TMP_DIR}/backup-readme-original.md" "${backup_readme}"

expect_failure "${TMP_DIR}/invalid-backup.out" sh "${REPO_ROOT}/install.sh" --restore ../bad --profile standard --current-profile full --source-dir "${REPO_ROOT}" --target "${restore_target}"
assert_contains "${TMP_DIR}/invalid-backup.out" 'invalid backup id'

# Preserve-mode restore never owns core.hooksPath, including when a user has
# changed it after the update that produced the retained backup.
preserve_restore_target="${TMP_DIR}/preserve-restore-target"
make_git_target "${preserve_restore_target}"
run_install --target "${preserve_restore_target}" --profile standard --enable-githooks --hook-conflict preserve
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${preserve_restore_target}" >"${TMP_DIR}/preserve-update.out"
preserve_backup_id="$(sed -n 's/^beryl: update backup \.beryl\/\.updates\/\([^[:space:]]*\)$/\1/p' "${TMP_DIR}/preserve-update.out")"
git -C "${preserve_restore_target}" config core.hooksPath user-after-update
sh "${REPO_ROOT}/install.sh" --restore "${preserve_backup_id}" --profile standard --current-profile standard --source-dir "${REPO_ROOT}" --current-source-dir "${update_source}" --target "${preserve_restore_target}" >"${TMP_DIR}/preserve-restore.out"
[[ "$(git -C "${preserve_restore_target}" config --local --get core.hooksPath)" == user-after-update ]] || fail 'preserve-mode restore changed user hooks'

# Adoption inventories an unlocked tree without mutation in dry-run mode, then
# writes only an ownership ledger for identical regular Beryl files. It can be
# updated normally afterwards; conflicts and symlinks remain pre-mutation
# refusals.
adopt_target="${TMP_DIR}/adopt-target"
run_install --target "${adopt_target}" --profile minimal
rm "${adopt_target}/.beryl/lock.json"
printf 'target-owned unknown\n' >"${adopt_target}/.beryl/local-note.txt"
snapshot_tree "${adopt_target}" "${TMP_DIR}/adopt-before.tar"
sh "${REPO_ROOT}/install.sh" --adopt-existing --dry-run --source-dir "${REPO_ROOT}" --target "${adopt_target}" >"${TMP_DIR}/adopt-dry.out"
assert_tree_unchanged "${adopt_target}" "${TMP_DIR}/adopt-before.tar"
sh "${REPO_ROOT}/install.sh" --adopt-existing --source-dir "${REPO_ROOT}" --target "${adopt_target}" >"${TMP_DIR}/adopt.out"
[[ -f "${adopt_target}/.beryl/lock.json" ]] || fail 'adoption did not write lock'
assert_contains "${adopt_target}/.beryl/lock.json" '"AGENTS.md"'
[[ "$(<"${adopt_target}/.beryl/local-note.txt")" == 'target-owned unknown' ]] || fail 'adoption changed unknown file'
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${adopt_target}" >"${TMP_DIR}/adopt-update.out"
sh "${REPO_ROOT}/install.sh" --uninstall --profile minimal --source-dir "${update_source}" --target "${adopt_target}" >"${TMP_DIR}/adopt-uninstall.out"
[[ ! -e "${adopt_target}/AGENTS.md" ]] || fail 'adoption uninstall left adopted root shim'
[[ "$(<"${adopt_target}/.beryl/local-note.txt")" == 'target-owned unknown' ]] || fail 'adoption uninstall removed unknown file'

for adopt_profile in standard full; do
  adopt_profile_target="${TMP_DIR}/adopt-${adopt_profile}"
  run_install --target "${adopt_profile_target}" --profile "${adopt_profile}"
  rm "${adopt_profile_target}/.beryl/lock.json"
  sh "${REPO_ROOT}/install.sh" --adopt-existing --source-dir "${REPO_ROOT}" --target "${adopt_profile_target}" >"${TMP_DIR}/adopt-${adopt_profile}.out"
  [[ -f "${adopt_profile_target}/.beryl/lock.json" ]] || fail "${adopt_profile} adoption did not write lock"
  ! grep -q 'skip:.beryl/' "${adopt_profile_target}/.beryl/lock.json" || fail "${adopt_profile} adoption recorded internal preserved path as root decision"
done

adopt_hooks="${TMP_DIR}/adopt-hooks"
make_git_target "${adopt_hooks}"
run_install --target "${adopt_hooks}" --profile standard --enable-githooks --hook-conflict replace
rm "${adopt_hooks}/.beryl/lock.json"
expect_failure "${TMP_DIR}/adopt-hooks.out" sh "${REPO_ROOT}/install.sh" --adopt-existing --source-dir "${REPO_ROOT}" --target "${adopt_hooks}"
assert_contains "${TMP_DIR}/adopt-hooks.out" 'adoption refuses active Beryl hooks'

adopt_conflict="${TMP_DIR}/adopt-conflict"
run_install --target "${adopt_conflict}" --profile minimal
rm "${adopt_conflict}/.beryl/lock.json"
printf 'not Beryl\n' >"${adopt_conflict}/.beryl/agent/README.md"
snapshot_tree "${adopt_conflict}" "${TMP_DIR}/adopt-conflict-before.tar"
expect_failure "${TMP_DIR}/adopt-conflict.out" sh "${REPO_ROOT}/install.sh" --adopt-existing --source-dir "${REPO_ROOT}" --target "${adopt_conflict}"
assert_contains "${TMP_DIR}/adopt-conflict.out" 'adoption requires identical staged files'
assert_tree_unchanged "${adopt_conflict}" "${TMP_DIR}/adopt-conflict-before.tar"

adopt_symlink="${TMP_DIR}/adopt-symlink"
run_install --target "${adopt_symlink}" --profile minimal
rm "${adopt_symlink}/.beryl/lock.json" "${adopt_symlink}/.beryl/agent/README.md"
ln -s "${symlink_external}" "${adopt_symlink}/.beryl/agent/README.md"
expect_failure "${TMP_DIR}/adopt-symlink.out" sh "${REPO_ROOT}/install.sh" --adopt-existing --source-dir "${REPO_ROOT}" --target "${adopt_symlink}"
assert_contains "${TMP_DIR}/adopt-symlink.out" 'adoption refuses symlinks'

printf 'recovery lifecycle tests passed\n'
