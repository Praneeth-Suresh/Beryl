#!/usr/bin/env bash
# Regression test for issue #43: the SHA test manifest mechanism is removed.
# Fresh installs must not create it, editing tests must not fail the gate, and
# updating an install that still has the legacy files must succeed without
# deleting them.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-test-manifest-removal.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

LEGACY_NAMES=(
  'update-test-manifest'
  'check-tests-unchanged'
  'test-manifest-lib'
  'test-manifest.conf'
  '.manifest.sha256'
)

# No tracked file other than this test may mention the removed mechanism.
for name in "${LEGACY_NAMES[@]}"; do
  if hits="$(git -C "${REPO_ROOT}" grep -n -F -e "${name}" -- . ':(exclude)tests/test-manifest-removal.sh' | grep -v -F '# legacy backups')"; then
    fail "tracked files still reference ${name}:
${hits}"
  fi
done

# A fresh standard install has no manifest artefacts, and a changed test file
# does not fail the deterministic gate.
fresh_target="${TMP_DIR}/fresh"
mkdir -p "${fresh_target}"
git -C "${fresh_target}" init -q
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${fresh_target}" \
  --profile standard >"${TMP_DIR}/fresh-install.out"
for legacy in tests/.manifest.sha256 .beryl/agent/test-manifest.conf \
  .beryl/scripts/update-test-manifest.sh .beryl/scripts/check-tests-unchanged.sh \
  .beryl/scripts/test-manifest-lib.sh; do
  [[ ! -e "${fresh_target}/${legacy}" ]] || fail "fresh install created ${legacy}"
done
mkdir -p "${fresh_target}/tests"
printf '#!/usr/bin/env bash\nexit 0\n' >"${fresh_target}/tests/example.sh"
(cd "${fresh_target}" && ./.beryl/scripts/check.sh) >"${TMP_DIR}/fresh-check-1.out"
printf '# intentional test edit\n' >>"${fresh_target}/tests/example.sh"
(cd "${fresh_target}" && ./.beryl/scripts/check.sh) >"${TMP_DIR}/fresh-check-2.out" || \
  fail 'check.sh failed after a test file changed'

# Build a legacy source checkout that still ships a manifest gate script. The
# script fails loudly so the test proves the updated gate no longer runs it.
legacy_source="${TMP_DIR}/legacy-source"
git clone -q "${REPO_ROOT}" "${legacy_source}"
while IFS= read -r -d '' rel; do
  mkdir -p "$(dirname "${legacy_source}/${rel}")"
  cp -p "${REPO_ROOT}/${rel}" "${legacy_source}/${rel}"
done < <(git -C "${REPO_ROOT}" ls-files -z)
printf '#!/usr/bin/env bash\necho "legacy manifest gate invoked" >&2\nexit 1\n' \
  >"${legacy_source}/.beryl/scripts/check-tests-unchanged.sh"
chmod 0755 "${legacy_source}/.beryl/scripts/check-tests-unchanged.sh"
git -C "${legacy_source}" add -A
git -C "${legacy_source}" -c user.email=beryl-tests@example.invalid \
  -c user.name='Beryl tests' commit -q -m 'legacy fixture'

legacy_target="${TMP_DIR}/legacy-target"
mkdir -p "${legacy_target}"
git -C "${legacy_target}" init -q
sh "${REPO_ROOT}/install.sh" --source-dir "${legacy_source}" --target "${legacy_target}" \
  --profile standard >"${TMP_DIR}/legacy-install.out"
grep -Fq '.beryl/scripts/check-tests-unchanged.sh' "${legacy_target}/.beryl/lock.json" || \
  fail 'legacy fixture did not record the manifest gate as managed'
mkdir -p "${legacy_target}/tests"
printf '0000  tests/legacy.sh\n' >"${legacy_target}/tests/.manifest.sha256"
printf 'MANIFEST_PATH="tests/.manifest.sha256"\n' >"${legacy_target}/.beryl/agent/test-manifest.conf"

sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${legacy_target}" \
  --update >"${TMP_DIR}/legacy-update.out" 2>&1 || {
  cat "${TMP_DIR}/legacy-update.out" >&2
  fail 'update from a legacy manifest install failed'
}
grep -Fq 'preserved ambiguous removed path .beryl/scripts/check-tests-unchanged.sh' \
  "${TMP_DIR}/legacy-update.out" || fail 'update did not report the dropped manifest gate'
if grep -Fq 'check-tests-unchanged' "${legacy_target}/.beryl/lock.json"; then
  fail 'update kept the removed manifest gate in the ownership ledger'
fi
for legacy in tests/.manifest.sha256 .beryl/agent/test-manifest.conf \
  .beryl/scripts/check-tests-unchanged.sh; do
  [[ -e "${legacy_target}/${legacy}" ]] || fail "update deleted target file ${legacy}"
done
(cd "${legacy_target}" && ./.beryl/scripts/check.sh) >"${TMP_DIR}/legacy-check.out" 2>&1 || {
  cat "${TMP_DIR}/legacy-check.out" >&2
  fail 'check.sh failed after updating a legacy manifest install'
}

printf 'test manifest removal tests passed\n'
