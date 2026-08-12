#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-readiness-contract.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT
INSTALL_SOURCE="${TMP_DIR}/install-source"

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
  grep -Fqx -- "${expected}" "${file}" || fail "${file} did not contain an exact line: ${expected}"
}

install_profile() {
  local target="$1"
  local profile="$2"

  mkdir -p "${target}"
  printf 'host-owned-ignore-rule\n' >"${target}/.gitignore"
  git -C "${target}" init -q
  sh "${INSTALL_SOURCE}/install.sh" --source-dir "${INSTALL_SOURCE}" --target "${target}" --profile "${profile}"
}

# The source checkout's .codex shim can be mounted read-only by the host
# runtime. Use a writable release-surface copy for install fixtures, then make
# its generated shim match the canonical template exactly.
cp -pR "${REPO_ROOT}/." "${INSTALL_SOURCE}/"
cp "${INSTALL_SOURCE}/.beryl/agent/tool-instruction-template.md" "${INSTALL_SOURCE}/.codex/AGENTS.md"

# Every profile gets the same seeded project context, including the generic
# ADR. A minimal install has no aggregate check component, so its direct
# readiness proof is the profile-aware doctor.
minimal_target="${TMP_DIR}/minimal"
install_profile "${minimal_target}" minimal
"${minimal_target}/.beryl/agent/scripts/agent-doctor.sh"
[[ -f "${minimal_target}/.beryl/agent/adr/0001-record-architecture-decisions.md" ]] || \
  fail 'minimal install did not seed the generic ADR'
assert_contains "${minimal_target}/.gitignore" 'host-owned-ignore-rule'
assert_contains "${minimal_target}/.gitignore" '.beryl/agent/session-state.md'
git -C "${minimal_target}" check-ignore -q .beryl/agent/session-state.md || \
  fail 'direct minimal install did not ignore session state'
[[ ! -e "${minimal_target}/.beryl/scripts/check.sh" ]] || \
  fail 'minimal install unexpectedly included the checks component'

# A lock is not self-authorizing. Doctor rejects both a forged resolved
# selection and a valid manifest path injected outside the selected surface.
cp "${minimal_target}/.beryl/lock.json" "${TMP_DIR}/minimal-lock-original.json"
sed 's/"components": \[/"components": ["driver",/' "${TMP_DIR}/minimal-lock-original.json" \
  >"${minimal_target}/.beryl/lock.json"
expect_failure "${TMP_DIR}/minimal-forged-components.out" \
  "${minimal_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'components do not match requested dependency closure' "${TMP_DIR}/minimal-forged-components.out" || \
  fail 'doctor accepted forged resolved component selection'
cp "${TMP_DIR}/minimal-lock-original.json" "${minimal_target}/.beryl/lock.json"
forged_driver_digest="$(sha256sum "${REPO_ROOT}/.beryl/driver/run.sh" | awk '{print $1}')"
sed \
  -e 's/"managedPaths": \[/"managedPaths": [".beryl\/driver\/run.sh",/' \
  -e "s/\"managedPathDigests\": \[/\"managedPathDigests\": [\".beryl\\/driver\\/run.sh:${forged_driver_digest}\",/" \
  "${TMP_DIR}/minimal-lock-original.json" >"${minimal_target}/.beryl/lock.json"
expect_failure "${TMP_DIR}/minimal-forged-surface.out" \
  "${minimal_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'managed path is outside selected surface: .beryl/driver/run.sh' "${TMP_DIR}/minimal-forged-surface.out" || \
  fail 'doctor accepted an outside-selected managed path'
cp "${TMP_DIR}/minimal-lock-original.json" "${minimal_target}/.beryl/lock.json"

# Standard and full profiles include the aggregate gate. It must now certify
# the installed contract rather than only the copied check scripts.
standard_target="${TMP_DIR}/standard"
install_profile "${standard_target}" standard
host_install_marker="${TMP_DIR}/host-install-was-executed"
printf '#!/usr/bin/env bash\ntouch %q\n' "${host_install_marker}" >"${standard_target}/install.sh"
chmod +x "${standard_target}/install.sh"
"${standard_target}/.beryl/agent/scripts/agent-doctor.sh"
"${standard_target}/.beryl/scripts/check.sh"
[[ ! -e "${host_install_marker}" ]] || fail 'readiness executed an unrelated host install.sh'

# A deliberate skipped root shim is an explicit external contract, not a
# stale Beryl shim. The lock records the exact observed digest and the doctor
# keeps the installation qualified-ready only while it remains unchanged.
preserved_target="${TMP_DIR}/preserved-root-contract"
mkdir -p "${preserved_target}"
printf 'host-owned ignore rule\n' >"${preserved_target}/.gitignore"
printf 'host-owned AGENTS contract\n' >"${preserved_target}/AGENTS.md"
cp "${preserved_target}/AGENTS.md" "${TMP_DIR}/preserved-agents-original"
git -C "${preserved_target}" init -q
sh "${INSTALL_SOURCE}/install.sh" --source-dir "${INSTALL_SOURCE}" --target "${preserved_target}" \
  --profile standard --root-conflict skip
"${preserved_target}/.beryl/scripts/check.sh" >"${TMP_DIR}/preserved-ready.out"
grep -Fq 'ready-with-preserved-external-contracts' "${TMP_DIR}/preserved-ready.out" || \
  fail 'aggregate gate did not report preserved external root-contract readiness'
grep -Fq 'WARNING: ready-with-preserved-external-contracts; Beryl does not enforce: AGENTS.md' "${TMP_DIR}/preserved-ready.out" || \
  fail 'aggregate gate did not name the preserved external shim'
grep -Fq '"preservedRootContractDigestsVersion": 1' "${preserved_target}/.beryl/lock.json" || \
  fail 'preserved root contract lock digest version is missing'
grep -Fq '"AGENTS.md:' "${preserved_target}/.beryl/lock.json" || \
  fail 'preserved root contract digest is missing'
printf 'changed external AGENTS contract\n' >"${preserved_target}/AGENTS.md"
expect_failure "${TMP_DIR}/preserved-changed.out" \
  "${preserved_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'preserved external root contract changed since install: AGENTS.md' "${TMP_DIR}/preserved-changed.out" || \
  fail 'doctor accepted a changed preserved root contract'
cp "${TMP_DIR}/preserved-agents-original" "${preserved_target}/AGENTS.md"
mv "${preserved_target}/AGENTS.md" "${preserved_target}/AGENTS.md.original"
ln -s "${TMP_DIR}/preserved-agents-original" "${preserved_target}/AGENTS.md"
expect_failure "${TMP_DIR}/preserved-symlink.out" \
  "${preserved_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'preserved external root contract must be a regular non-symlink file: AGENTS.md' "${TMP_DIR}/preserved-symlink.out" || \
  fail 'doctor accepted a symlinked preserved root contract'
rm "${preserved_target}/AGENTS.md"
mv "${preserved_target}/AGENTS.md.original" "${preserved_target}/AGENTS.md"
sed -i 's/"skip:AGENTS.md"/"skip:AGENTS.md","skip:AGENTS.md"/' "${preserved_target}/.beryl/lock.json"
expect_failure "${TMP_DIR}/preserved-duplicate.out" \
  "${preserved_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'invalid lockfile: duplicate root conflict decision: AGENTS.md' "${TMP_DIR}/preserved-duplicate.out" || \
  fail 'doctor accepted duplicate preserved root-contract decisions'

# Aggregate readiness must run the doctor before any child script. Replacing a
# shared dependency with an external payload therefore fails without running
# the payload.
aggregate_payload_marker="${TMP_DIR}/aggregate-paths-ran"
aggregate_payload="${TMP_DIR}/aggregate-paths-payload.sh"
printf '#!/usr/bin/env bash\ntouch %q\n' "${aggregate_payload_marker}" >"${aggregate_payload}"
mv "${standard_target}/.beryl/scripts/paths.sh" "${standard_target}/.beryl/scripts/paths.sh.original"
ln -s "${aggregate_payload}" "${standard_target}/.beryl/scripts/paths.sh"
expect_failure "${TMP_DIR}/aggregate-paths-symlink.out" "${standard_target}/.beryl/scripts/check.sh"
grep -Fq 'managed path must not be a symlink: .beryl/scripts/paths.sh' "${TMP_DIR}/aggregate-paths-symlink.out" || \
  fail 'aggregate gate did not reject the symlinked paths dependency'
[[ ! -e "${aggregate_payload_marker}" ]] || fail 'aggregate gate executed a child dependency before doctor verification'
rm "${standard_target}/.beryl/scripts/paths.sh"
mv "${standard_target}/.beryl/scripts/paths.sh.original" "${standard_target}/.beryl/scripts/paths.sh"

full_target="${TMP_DIR}/full"
install_profile "${full_target}" full
"${full_target}/.beryl/agent/scripts/agent-doctor.sh"
"${full_target}/.beryl/scripts/check.sh"

# Explicit component selection has no profile name in the lock. The doctor
# must use the resolved component ledger and require only that selection.
custom_target="${TMP_DIR}/custom"
mkdir -p "${custom_target}"
printf 'host-owned-ignore-rule\n' >"${custom_target}/.gitignore"
git -C "${custom_target}" init -q
sh "${INSTALL_SOURCE}/install.sh" --source-dir "${INSTALL_SOURCE}" --target "${custom_target}" \
  --components agent-core,tool-shims,checks
"${custom_target}/.beryl/agent/scripts/agent-doctor.sh"
"${custom_target}/.beryl/scripts/check.sh"
[[ ! -e "${custom_target}/.beryl/githooks/pre-commit" ]] || \
  fail 'custom install unexpectedly required or included githooks'

# The doctor must reject a symlinked dependency before sourcing it. The
# external payload would create a marker if it ever ran.
external_marker="${TMP_DIR}/external-source-ran"
external_safe_conf="${TMP_DIR}/external-safe-conf.sh"
printf '#!/usr/bin/env bash\ntouch %q\n' "${external_marker}" >"${external_safe_conf}"
rm "${custom_target}/.beryl/scripts/safe-conf.sh"
ln -s "${external_safe_conf}" "${custom_target}/.beryl/scripts/safe-conf.sh"
expect_failure "${TMP_DIR}/safe-conf-symlink.out" \
  "${custom_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'managed path must not be a symlink: .beryl/scripts/safe-conf.sh' "${TMP_DIR}/safe-conf-symlink.out" || \
  fail 'doctor did not reject the symlinked safe-conf dependency'
[[ ! -e "${external_marker}" ]] || fail 'doctor executed the external symlink payload'

# A missing seeded artifact is a readiness failure even though the lock still
# names agent-core. A stale generated root contract must also make the
# aggregate gate nonzero rather than reporting a false green result.
rm "${standard_target}/.beryl/agent/adr/0001-record-architecture-decisions.md"
expect_failure "${TMP_DIR}/missing-adr.out" \
  "${standard_target}/.beryl/agent/scripts/agent-doctor.sh"
grep -Fq 'missing file: .beryl/agent/adr/0001-record-architecture-decisions.md' "${TMP_DIR}/missing-adr.out" || \
  fail 'doctor did not identify the missing generic ADR'

# Deleting the lock must make both doctor and the aggregate gate fail, even
# when an unrelated host install.sh is present. Neither command may execute
# that host script as a readiness heuristic.
printf 'Beryl source checkout marker v1\n' >"${standard_target}/.beryl/source-checkout.marker"
rm "${standard_target}/.beryl/lock.json"
expect_failure "${TMP_DIR}/missing-lock-doctor.out" \
  "${standard_target}/.beryl/agent/scripts/agent-doctor.sh"
expect_failure "${TMP_DIR}/missing-lock-check.out" \
  "${standard_target}/.beryl/scripts/check.sh"
grep -Fq 'missing lockfile: .beryl/lock.json' "${TMP_DIR}/missing-lock-doctor.out" || \
  fail 'doctor did not report the missing lockfile'
grep -Fq 'missing lockfile: .beryl/lock.json' "${TMP_DIR}/missing-lock-check.out" || \
  fail 'aggregate gate did not report the missing lockfile'
[[ ! -e "${host_install_marker}" ]] || fail 'missing-lock readiness executed an unrelated host install.sh'

# The bootstrap path must reject a parent .beryl symlink before either entry
# point resolves directories or sources the external paths.sh payload.
symlink_target="${TMP_DIR}/symlink-target"
external_beryl="${TMP_DIR}/external-beryl"
external_symlink_marker="${TMP_DIR}/external-paths-ran"
mkdir -p "${symlink_target}" "${external_beryl}"
cp -pR "${REPO_ROOT}/.beryl/." "${external_beryl}/"
printf '#!/usr/bin/env bash\ntouch %q\n' "${external_symlink_marker}" >"${external_beryl}/scripts/paths.sh"
chmod +x "${external_beryl}/scripts/paths.sh"
ln -s "${external_beryl}" "${symlink_target}/.beryl"
expect_failure "${TMP_DIR}/symlink-doctor.out" \
  "${symlink_target}/.beryl/agent/scripts/agent-doctor.sh"
expect_failure "${TMP_DIR}/symlink-check.out" \
  "${symlink_target}/.beryl/scripts/check.sh"
grep -Fq 'invoked script path has a symlink ancestor' "${TMP_DIR}/symlink-doctor.out" || \
  fail 'doctor did not reject the parent .beryl symlink'
grep -Fq 'invoked script path has a symlink ancestor' "${TMP_DIR}/symlink-check.out" || \
  fail 'aggregate check did not reject the parent .beryl symlink'
[[ ! -e "${external_symlink_marker}" ]] || fail 'entry point sourced external paths.sh through a .beryl symlink'

printf 'stale target-owned shim\n' >"${full_target}/AGENTS.md"
expect_failure "${TMP_DIR}/stale-shim.out" "${full_target}/.beryl/scripts/check.sh"
grep -Fq 'stale shim: AGENTS.md' "${TMP_DIR}/stale-shim.out" || \
  fail 'aggregate gate did not report the stale shim'

# The Beryl source checkout retains its documented default command through a
# tracked Beryl-owned marker, and explicit development mode remains available
# for source CI without using any host filename as a signal.
"${INSTALL_SOURCE}/.beryl/agent/scripts/agent-doctor.sh" --development
"${INSTALL_SOURCE}/.beryl/scripts/check.sh" --development

printf 'readiness contract tests passed\n'
