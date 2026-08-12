#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-portability.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

install_profile() {
  local profile="$1"
  local target="${TMP_DIR}/${profile}"

  sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${target}" --profile "${profile}"
  [[ -f "${target}/.beryl/lock.json" ]] || fail "${profile}: lockfile was not written"
  [[ -f "${target}/AGENTS.md" ]] || fail "${profile}: generated shim missing"
  [[ -f "${target}/LICENSE" ]] || fail "${profile}: Apache license missing"
  [[ -f "${target}/NOTICE" ]] || fail "${profile}: Apache notice missing"
  [[ -f "${target}/.beryl/agent/skills/initial-build/SKILL.md" ]] || \
    fail "${profile}: initial-build skill missing"
  [[ ! -e "${target}/.beryl/agent/hierarchy.md" ]] || \
    fail "${profile}: hierarchy.md must not be created during install"

  if [[ "${profile}" != "minimal" ]]; then
    (cd "${target}" && ./.beryl/scripts/check.sh)
  fi

  if [[ "${profile}" == "full" ]]; then
    (cd "${target}" && DRIVER_MOCK=1 bash .beryl/driver/run.sh --selftest)
    (cd "${target}" && bash .beryl/driver/optimize-worktrees.sh --selftest)
  fi
}

install_profile minimal
install_profile standard
install_profile full

copy_update_source() {
  local destination="$1"
  local rel source destination_file

  # Keep current candidate changes while respecting the same tracked-release
  # boundary that local --source-dir enforces. The clone supplies Git metadata;
  # only current tracked regular files are overlaid and staged.
  git clone -q "${REPO_ROOT}" "${destination}"
  while IFS= read -r -d '' rel; do
    source="${REPO_ROOT}/${rel}"
    destination_file="${destination}/${rel}"
    [[ ! -L "${source}" ]] || fail "update source fixture must not copy symlink: ${rel}"
    [[ -f "${source}" ]] || fail "update source fixture tracked file missing or unsupported: ${rel}"
    mkdir -p "$(dirname "${destination_file}")"
    cp -p "${source}" "${destination_file}"
  done < <(git -C "${REPO_ROOT}" ls-files -z)
  git -C "${destination}" add -u
}

lock_array_has() {
  local lockfile="$1"
  local field="$2"
  local value="$3"

  sed -n "s/^  \\\"${field}\\\": \\[\\(.*\\)\\].*$/\\1/p" "${lockfile}" | \
    tr ',' '\n' | sed 's/^"//; s/"$//' | grep -qxF "${value}"
}

assert_file_contains() {
  local file="$1"
  local expected="$2"
  local label="$3"

  grep -qF -- "${expected}" "${file}" || fail "${label}: expected ${file} to contain ${expected}"
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
  cmp -s "${before}" "${after}" || fail "target changed after rejected lifecycle operation: ${source}"
}

update_source="${TMP_DIR}/update-source"
copy_update_source "${update_source}"
printf '\nissue-28-updated-managed-feature\n' >>"${update_source}/.beryl/driver/README.md"
printf '#!/bin/sh\nprintf "issue-28 managed feature\\n"\n' \
  >"${update_source}/.beryl/driver/issue28-update-feature.sh"
chmod +x "${update_source}/.beryl/driver/issue28-update-feature.sh"
git -C "${update_source}" init -q
git -C "${update_source}" add -A
git -C "${update_source}" -c user.email=tests@example.invalid -c user.name='Beryl tests' \
  commit -qm 'release fixture'

# Start from a full, populated installation and deliberately downgrade its
# lockfile to the pre-update schema. This proves the update migration is safe
# for installations created before the managed-path ledger existed.
update_target="${TMP_DIR}/update-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${update_target}" --profile full
printf 'repository-specific brief\n' >"${update_target}/.beryl/agent/project-brief.md"
printf 'repository-specific architecture\n' >"${update_target}/.beryl/agent/architecture.md"
printf 'active local session\n' >"${update_target}/.beryl/agent/session-state.md"
mkdir -p "${update_target}/.beryl/agent/custom-settings"
printf 'CUSTOM_SETTING=keep\n' >"${update_target}/.beryl/agent/custom-settings/local.env"
printf '# repository affected-test configuration\n' >"${update_target}/.beryl/agent/affected-tests.conf"
printf 'MANIFEST_PATH="tests/local-manifest.sha256"\n' >"${update_target}/.beryl/agent/test-manifest.conf"
printf 'LOCAL_DRIVER_CONFIG=keep\n' >"${update_target}/.beryl/driver/config.env"
printf 'user-owned driver task\n' >"${update_target}/.beryl/driver/tasks/99-user-task.md"
printf 'user-owned beryl file\n' >"${update_target}/.beryl/user-added.txt"
printf 'user-owned root file\n' >"${update_target}/repository-notes.txt"
legacy_lock="${update_target}/.beryl/lock.json"
awk '!/"managedPathsVersion"/ && !/"managedPaths"/' "${legacy_lock}" >"${legacy_lock}.legacy"
mv "${legacy_lock}.legacy" "${legacy_lock}"

update_output="${TMP_DIR}/update-success.out"
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${update_target}" \
  >"${update_output}" 2>&1 || fail "update: expected legacy installation update to succeed"
[[ -f "${update_target}/.beryl/driver/issue28-update-feature.sh" ]] || \
  fail 'update: new managed driver feature missing'
assert_file_contains "${update_target}/.beryl/driver/README.md" \
  'issue-28-updated-managed-feature' 'update'
assert_file_contains "${update_target}/.beryl/agent/project-brief.md" \
  'repository-specific brief' 'update preservation'
assert_file_contains "${update_target}/.beryl/agent/architecture.md" \
  'repository-specific architecture' 'update preservation'
assert_file_contains "${update_target}/.beryl/agent/session-state.md" \
  'active local session' 'update preservation'
assert_file_contains "${update_target}/.beryl/agent/custom-settings/local.env" \
  'CUSTOM_SETTING=keep' 'manifest-owned update preservation'
assert_file_contains "${update_target}/.beryl/agent/affected-tests.conf" \
  'repository affected-test configuration' 'update preservation'
assert_file_contains "${update_target}/.beryl/agent/test-manifest.conf" \
  'tests/local-manifest.sha256' 'update preservation'
assert_file_contains "${update_target}/.beryl/driver/config.env" \
  'LOCAL_DRIVER_CONFIG=keep' 'update preservation'
assert_file_contains "${update_target}/.beryl/driver/tasks/99-user-task.md" \
  'user-owned driver task' 'update preservation'
assert_file_contains "${update_target}/.beryl/user-added.txt" \
  'user-owned beryl file' 'update preservation'
assert_file_contains "${update_target}/repository-notes.txt" \
  'user-owned root file' 'update preservation'
lock_array_has "${update_target}/.beryl/lock.json" requestedComponents driver || \
  fail 'update: retained full installation did not retain driver selection'
assert_file_contains "${update_target}/.beryl/lock.json" '"managedPathsVersion": 1' 'update ledger'
assert_file_contains "${update_output}" 'beryl: update complete' 'update summary'
assert_file_contains "${update_output}" 'updated' 'update summary'
assert_file_contains "${update_output}" 'preserved' 'update summary'

# Agent bootstrap may change external state, so update mode rejects it before
# staging and leaves the target byte-identical.
bootstrap_update_target="${TMP_DIR}/update-bootstrap-rejected"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${bootstrap_update_target}" --profile full
cp "${bootstrap_update_target}/.beryl/lock.json" "${TMP_DIR}/bootstrap-lock-before.json"
bootstrap_output="${TMP_DIR}/update-bootstrap-rejected.out"
if sh "${REPO_ROOT}/install.sh" --update --bootstrap-agent --source-dir "${update_source}" \
  --target "${bootstrap_update_target}" >"${bootstrap_output}" 2>&1; then
  fail 'update bootstrap: non-transactional bootstrap unexpectedly accepted'
fi
assert_file_contains "${bootstrap_output}" \
  '--bootstrap-agent is a standalone action' \
  'update bootstrap diagnostic'
cmp -s "${TMP_DIR}/bootstrap-lock-before.json" "${bootstrap_update_target}/.beryl/lock.json" || \
  fail 'update bootstrap: lockfile changed before bootstrap rejection'
[[ ! -e "${bootstrap_update_target}/.beryl/agent/bootstrap-status.json" ]] || \
  fail 'update bootstrap: bootstrap status changed before rejection'
[[ ! -e "${bootstrap_update_target}/.beryl/agent/bootstrap-runner.log" ]] || \
  fail 'update bootstrap: bootstrap log changed before rejection'

# An explicit component override must be able to opt a standard installation
# into a newly available component without relying on the default profile.
override_target="${TMP_DIR}/update-override"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${override_target}" --profile standard
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${override_target}" \
  --components driver >"${TMP_DIR}/update-override.out" 2>&1 || \
  fail 'update override: expected explicit driver selection to succeed'
lock_array_has "${override_target}/.beryl/lock.json" requestedComponents driver || \
  fail 'update override: requested driver component was not recorded'
[[ -f "${override_target}/.beryl/driver/issue28-update-feature.sh" ]] || \
  fail 'update override: driver feature missing after explicit selection'

# A profile reduction cannot use a prior lock as deletion authority: deselected
# runtime files remain visible for an explicit later uninstall/migration.
downgrade_target="${TMP_DIR}/update-downgrade"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${downgrade_target}" --profile full
printf 'DRIVER_CONFIG=keep\n' >"${downgrade_target}/.beryl/driver/config.env"
printf 'driver task sentinel\n' >"${downgrade_target}/.beryl/driver/tasks/99-preserved.md"
mkdir -p "${downgrade_target}/.beryl/driver/state/local"
printf 'state sentinel\n' >"${downgrade_target}/.beryl/driver/state/local/status.txt"
sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${downgrade_target}" \
  --profile standard >"${TMP_DIR}/update-downgrade.out" 2>&1 || \
  fail 'update downgrade: expected full-to-standard update to succeed'
[[ -e "${downgrade_target}/.beryl/driver/run.sh" ]] || \
  fail 'update downgrade: ambiguous managed driver runtime was deleted'
assert_file_contains "${downgrade_target}/.beryl/driver/config.env" \
  'DRIVER_CONFIG=keep' 'update downgrade preservation'
assert_file_contains "${downgrade_target}/.beryl/driver/tasks/99-preserved.md" \
  'driver task sentinel' 'update downgrade preservation'
assert_file_contains "${downgrade_target}/.beryl/driver/state/local/status.txt" \
  'state sentinel' 'update downgrade preservation'

# A forced mid-apply failure must leave both the managed content and the
# previous lock untouched, while reporting the concrete failed path.
rollback_target="${TMP_DIR}/update-rollback"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${rollback_target}" --profile full
cp "${rollback_target}/.beryl/lock.json" "${TMP_DIR}/rollback-lock-before.json"
cp "${rollback_target}/.beryl/driver/README.md" "${TMP_DIR}/rollback-driver-readme-before.md"
rollback_output="${TMP_DIR}/update-rollback.out"
if BERYL_UPDATE_FAIL_AT='apply:.beryl/driver/issue28-update-feature.sh' \
  sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${rollback_target}" \
  >"${rollback_output}" 2>&1; then
  fail 'update rollback: forced apply failure unexpectedly succeeded'
fi
assert_file_contains "${rollback_output}" 'beryl: update failed phase=apply' 'update rollback diagnostic'
assert_file_contains "${rollback_output}" '.beryl/driver/issue28-update-feature.sh' 'update rollback diagnostic'
assert_file_contains "${rollback_output}" 'rollback=' 'update rollback diagnostic'
cmp -s "${TMP_DIR}/rollback-lock-before.json" "${rollback_target}/.beryl/lock.json" || \
  fail 'update rollback: lockfile changed after failed update'
cmp -s "${TMP_DIR}/rollback-driver-readme-before.md" "${rollback_target}/.beryl/driver/README.md" || \
  fail 'update rollback: managed file was not restored'
[[ ! -e "${rollback_target}/.beryl/driver/issue28-update-feature.sh" ]] || \
  fail 'update rollback: new managed file remained after failed update'

# A lockfile ledger is untrusted update input. An entry outside the component
# ownership surface must fail before it can schedule a user file for removal.
tampered_lock_target="${TMP_DIR}/update-tampered-lock-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${tampered_lock_target}" --profile full
printf 'user-owned ledger sentinel\n' >"${tampered_lock_target}/.beryl/user-added.txt"
tampered_lock="${tampered_lock_target}/.beryl/lock.json"
sed 's/"managedPaths": \[/"managedPaths": [".beryl\/user-added.txt",/' "${tampered_lock}" \
  >"${tampered_lock}.next"
mv "${tampered_lock}.next" "${tampered_lock}"
cp "${tampered_lock}" "${TMP_DIR}/tampered-lock-before.json"
tampered_lock_output="${TMP_DIR}/update-tampered-lock.out"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${tampered_lock_target}" \
  >"${tampered_lock_output}" 2>&1; then
  fail 'update tampered lock: unowned ledger entry unexpectedly accepted'
fi
assert_file_contains "${tampered_lock_output}" \
  'beryl: update failed phase=validate component=lockfile path=.beryl/user-added.txt reason=unowned-managed-path' \
  'update tampered lock diagnostic'
assert_file_contains "${tampered_lock_target}/.beryl/user-added.txt" \
  'user-owned ledger sentinel' 'update tampered lock preservation'
cmp -s "${TMP_DIR}/tampered-lock-before.json" "${tampered_lock}" || \
  fail 'update tampered lock: lockfile changed after validation failure'

# A forged digest is still not deletion authority: a ledger path must be
# selected by the independently staged historical component manifest.
forged_authority_target="${TMP_DIR}/update-forged-authority-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${forged_authority_target}" --profile full
printf 'user-owned forged authority sentinel\n' >"${forged_authority_target}/.beryl/user-owned.txt"
forged_digest="$(sha256sum "${forged_authority_target}/.beryl/user-owned.txt" | awk '{print $1}')"
forged_lock="${forged_authority_target}/.beryl/lock.json"
sed \
  -e 's/"managedPaths": \[/"managedPaths": [".beryl\/user-owned.txt",/' \
  -e "s/\"managedPathDigests\": \[/\"managedPathDigests\": [\".beryl\\/user-owned.txt:${forged_digest}\",/" \
  "${forged_lock}" >"${forged_lock}.next"
mv "${forged_lock}.next" "${forged_lock}"
cp "${forged_lock}" "${TMP_DIR}/forged-authority-lock-before.json"
forged_authority_output="${TMP_DIR}/update-forged-authority.out"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" \
  --target "${forged_authority_target}" --profile standard >"${forged_authority_output}" 2>&1; then
  fail 'update forged authority: unselected valid-digest path unexpectedly accepted'
fi
assert_file_contains "${forged_authority_output}" 'path-not-selected-by-historical-manifest' 'update forged authority diagnostic'
assert_file_contains "${forged_authority_target}/.beryl/user-owned.txt" \
  'user-owned forged authority sentinel' 'update forged authority preservation'
cmp -s "${TMP_DIR}/forged-authority-lock-before.json" "${forged_lock}" || \
  fail 'update forged authority: lockfile changed after refusal'

# Local source staging requires a tracked release checkout. A copied directory
# is rejected before target mutation, with a stage diagnostic that names the
# source boundary rather than a later missing component file.
stage_failure_source="${TMP_DIR}/update-stage-failure-source"
copy_update_source "${stage_failure_source}"
# Retain current candidate files but deliberately remove Git metadata for this
# negative source-boundary case.
mv "${stage_failure_source}/.git" "${TMP_DIR}/update-stage-failure-source.git"
stage_failure_target="${TMP_DIR}/update-stage-failure-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${stage_failure_target}" --profile full
cp "${stage_failure_target}/.beryl/lock.json" "${TMP_DIR}/update-stage-failure-lock-before.json"
stage_failure_output="${TMP_DIR}/update-stage-failure.out"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${stage_failure_source}" \
  --target "${stage_failure_target}" >"${stage_failure_output}" 2>&1; then
  fail 'update stage failure: missing managed source unexpectedly succeeded'
fi
assert_file_contains "${stage_failure_output}" \
  'beryl: update failed phase=stage component=source-tree' \
  'update stage diagnostic'
assert_file_contains "${stage_failure_output}" \
  'local --source-dir must be a Git checkout' \
  'update stage diagnostic'
cmp -s "${TMP_DIR}/update-stage-failure-lock-before.json" \
  "${stage_failure_target}/.beryl/lock.json" || \
  fail 'update stage failure: target lock changed before source rejection'

# A managed leaf symlink is hostile state. The updater must reject it before
# mutation and leave both the target symlink and external referent unchanged.
symlink_target="${TMP_DIR}/update-symlink-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${symlink_target}" --profile full
external_readme="${TMP_DIR}/external-driver-readme.md"
printf 'external content must survive\n' >"${external_readme}"
printf '#!/bin/sh\nexit 0\n' >"${symlink_target}/.beryl/scripts/user-local.sh"
chmod 0644 "${symlink_target}/.beryl/scripts/user-local.sh"
rm -f "${symlink_target}/.beryl/driver/README.md"
ln -s "${external_readme}" "${symlink_target}/.beryl/driver/README.md"
snapshot_tree "${symlink_target}" "${TMP_DIR}/update-symlink-before.tar"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${symlink_target}" \
  >"${TMP_DIR}/update-symlink.out" 2>&1; then
  fail 'update symlink: managed leaf unexpectedly accepted'
fi
assert_file_contains "${TMP_DIR}/update-symlink.out" 'leaf-symlink' 'update leaf symlink diagnostic'
[[ -L "${symlink_target}/.beryl/driver/README.md" ]] || \
  fail 'update symlink: managed leaf symlink changed after rejection'
assert_file_contains "${external_readme}" 'external content must survive' 'update symlink protection'
assert_tree_unchanged "${symlink_target}" "${TMP_DIR}/update-symlink-before.tar"

# Parent symlinks are rejected before mutation, so no update write can escape
# the selected target directory.
parent_symlink_target="${TMP_DIR}/update-parent-symlink-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${parent_symlink_target}" --profile full
external_driver_dir="${TMP_DIR}/external-driver-dir"
mv "${parent_symlink_target}/.beryl/driver" "${external_driver_dir}"
ln -s "${external_driver_dir}" "${parent_symlink_target}/.beryl/driver"
parent_symlink_output="${TMP_DIR}/update-parent-symlink.out"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${parent_symlink_target}" \
  >"${parent_symlink_output}" 2>&1; then
  fail 'update parent symlink: external parent unexpectedly accepted'
fi
assert_file_contains "${parent_symlink_output}" \
  'beryl: update failed phase=snapshot component=driver path=.beryl/driver/' \
  'update parent symlink diagnostic'
assert_file_contains "${external_driver_dir}/README.md" 'Agent Driver' 'update parent symlink protection'

# The backup location is target-owned too: it must be guarded before mkdir so
# a pre-existing .updates symlink cannot receive Beryl's rollback data.
backup_symlink_target="${TMP_DIR}/update-backup-symlink-target"
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${backup_symlink_target}" --profile full
external_backup_dir="${TMP_DIR}/external-backup-dir"
mkdir -p "${external_backup_dir}"
ln -s "${external_backup_dir}" "${backup_symlink_target}/.beryl/.updates"
backup_symlink_output="${TMP_DIR}/update-backup-symlink.out"
if sh "${REPO_ROOT}/install.sh" --update --source-dir "${update_source}" --target "${backup_symlink_target}" \
  >"${backup_symlink_output}" 2>&1; then
  fail 'update backup symlink: external backup directory unexpectedly accepted'
fi
assert_file_contains "${backup_symlink_output}" \
  'beryl: update failed phase=backup component=backup path=.beryl/.updates/' \
  'update backup symlink diagnostic'
[[ -z "$(find "${external_backup_dir}" -mindepth 1 -print -quit)" ]] || \
  fail 'update backup symlink: external backup directory was modified'

# Git config is outside the managed file ledger. A post-hook failure must
# restore the prior local hooks path after --enable-githooks changed it.
githooks_target="${TMP_DIR}/update-githooks-rollback-target"
mkdir -p "${githooks_target}"
git -C "${githooks_target}" init -q
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${githooks_target}" --profile full
git -C "${githooks_target}" config --local core.hooksPath previous-hooks
rm -f "${githooks_target}/.beryl/agent/adr/0001-record-architecture-decisions.md"
rm -f "${githooks_target}/tests/.manifest.sha256"
printf '#!/bin/sh\nexit 0\n' >"${githooks_target}/.beryl/scripts/user-local.sh"
chmod 0644 "${githooks_target}/.beryl/scripts/user-local.sh"
githooks_output="${TMP_DIR}/update-githooks-rollback.out"
if BERYL_UPDATE_FAIL_AT='verify:.beryl/driver/README.md' \
  sh "${REPO_ROOT}/install.sh" --update --enable-githooks --source-dir "${update_source}" \
  --hook-conflict replace --target "${githooks_target}" >"${githooks_output}" 2>&1; then
  fail 'update githooks rollback: forced verification failure unexpectedly succeeded'
fi
assert_file_contains "${githooks_output}" 'beryl: update failed phase=verify' \
  'update githooks rollback diagnostic'
[[ "$(git -C "${githooks_target}" config --local --get core.hooksPath)" == 'previous-hooks' ]] || \
  fail 'update githooks rollback: core.hooksPath was not restored'
[[ ! -e "${githooks_target}/.beryl/agent/adr/0001-record-architecture-decisions.md" ]] || \
  fail 'update hook rollback: seeded ADR remained after failed update'
[[ ! -e "${githooks_target}/tests/.manifest.sha256" ]] || \
  fail 'update hook rollback: configured test manifest remained after failed update'
[[ ! -x "${githooks_target}/.beryl/scripts/user-local.sh" ]] || \
  fail 'update permission rollback: user script mode changed after failed update'

setup_target="${TMP_DIR}/setup"
mkdir -p "${setup_target}"
bash "${REPO_ROOT}/.beryl/scripts/setup-project.sh" --non-interactive --profile standard \
  --stack generic --test-runner none --skip-check "${setup_target}" </dev/null
[[ -x "${setup_target}/.beryl/scripts/check.sh" ]] || fail 'setup: check.sh missing'
[[ -f "${setup_target}/AGENTS.md" ]] || fail 'setup: generated shim missing'
[[ -f "${setup_target}/LICENSE" ]] || fail 'setup: Apache license missing'
[[ -f "${setup_target}/NOTICE" ]] || fail 'setup: Apache notice missing'
[[ -f "${setup_target}/tests/.manifest.sha256" ]] || fail 'setup: test manifest missing'
[[ -f "${setup_target}/.beryl/agent/skills/initial-build/SKILL.md" ]] || fail 'setup: initial-build skill missing'
[[ ! -e "${setup_target}/.beryl/agent/hierarchy.md" ]] || fail 'setup: hierarchy.md must not be created during install'
(cd "${setup_target}" && ./.beryl/scripts/check.sh)

printf 'portability-smoke: PASS\n'
