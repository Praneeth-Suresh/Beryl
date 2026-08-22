#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local text="$2"
  grep -Fq -- "$text" "${REPO_ROOT}/${file}" || fail "${file} missing: ${text}"
}

assert_matches() {
  local file="$1"
  local pattern="$2"
  grep -Eq -- "$pattern" "${REPO_ROOT}/${file}" || fail "${file} missing pattern: ${pattern}"
}

assert_help_contains() {
  local text="$1"
  sh "${REPO_ROOT}/install.sh" --help | grep -Fq -- "$text" || \
    fail "install.sh --help missing: ${text}"
}

public_docs=(
  README.md
  Quickstart.md
  Cheatsheet.md
  .beryl/scripts/README.md
  .beryl/agent/skills/using-beryl/SKILL.md
  SECURITY.md
  SUPPORT.md
)

for file in "${public_docs[@]}"; do
  [[ -f "${REPO_ROOT}/${file}" ]] || fail "missing public document: ${file}"
  if grep -Eq 'raw\.githubusercontent\.com/[^[:space:]"`]+/main/install\.sh' "${REPO_ROOT}/${file}"; then
    fail "${file} has a mutable main installer URL"
  fi
  if grep -Eqi '(curl|wget)[^`\n]*\|[[:space:]]*(ba)?sh([[:space:]]|$)' "${REPO_ROOT}/${file}"; then
    fail "${file} has an unsafe pipe-to-shell installer command"
  fi
  if grep -Eq "BERYL_REF=['\"]?v[0-9]" "${REPO_ROOT}/${file}"; then
    fail "${file} uses a tag where a remote full commit SHA is required"
  fi
  if grep -Fq -- '--previous-source-dir' "${REPO_ROOT}/${file}"; then
    fail "${file} documents removed --previous-source-dir behavior"
  fi
done

# Every downloadable installer command must derive its URL from the selected
# ref, apply HTTPS redirect/TLS controls, and ask the installer to verify the
# trusted release archive. PowerShell refuses redirects rather than following
# them, then hands the file to Git Bash or WSL.
for file in README.md Quickstart.md .beryl/scripts/README.md .beryl/agent/skills/using-beryl/SKILL.md; do
  assert_matches "$file" 'raw\.githubusercontent\.com/Praneeth-Suresh/Beryl/\$\{?BERYL_REF\}?/install\.sh|raw\.githubusercontent\.com/Praneeth-Suresh/Beryl/\$env:BERYL_REF/install\.sh'
  assert_contains "$file" '--expected-sha256'
  assert_contains "$file" '0123456789abcdef0123456789abcdef01234567'
  assert_contains "$file" '40-character commit SHA'
  assert_contains "$file" 'github.com/Praneeth-Suresh/Beryl/releases'
done

for file in README.md Quickstart.md .beryl/scripts/README.md .beryl/agent/skills/using-beryl/SKILL.md; do
  assert_contains "$file" "--proto '=https'"
  assert_contains "$file" "--proto-redir '=https'"
  assert_contains "$file" '--tlsv1.2'
done

# The recommended path must name the signed bootstrap and make the independent
# first-trust boundary explicit. Manual fallback content may retain PowerShell
# redirect hardening where it documents the pinned installer.
for file in README.md Quickstart.md .beryl/scripts/README.md .beryl/agent/skills/using-beryl/SKILL.md; do
  assert_contains "$file" 'beryl-bootstrap.sh'
  assert_contains "$file" 'independently trusted'
done

assert_contains README.md '--source-dir'
assert_contains README.md 'Git checkout'
assert_contains .beryl/scripts/README.md '--non-interactive'
assert_contains .beryl/scripts/README.md '--root-conflict fail|skip|overwrite'
assert_contains .beryl/scripts/README.md '--hook-conflict fail|preserve|replace'
assert_contains .beryl/scripts/README.md '--bootstrap-agent'
assert_contains .beryl/scripts/README.md '--restore <backup-id>'
assert_contains .beryl/scripts/README.md '--uninstall'
assert_contains .beryl/scripts/README.md '--adopt-existing'
assert_contains .beryl/scripts/README.md '--current-source-dir'
assert_contains .beryl/scripts/README.md '--current-profile NAME'
assert_contains .beryl/scripts/README.md '--current-components a,b'
assert_contains .beryl/scripts/README.md 'expectedSourceSha256'
assert_contains .beryl/scripts/README.md 'ambiguous or partial surfaces'
assert_contains .beryl/scripts/README.md 'ledger is state, not destructive authority'
assert_contains .beryl/scripts/README.md 'selection change is never cleanup authorization'
assert_contains .beryl/scripts/README.md 'requires explicit `--profile` or `--components`'
assert_contains .beryl/scripts/README.md 'historical `--profile`/`--components`'
assert_contains .beryl/scripts/README.md '`--current-profile`/`--current-components`'
assert_contains .beryl/scripts/README.md 'immutable `sourceRef`'
assert_contains .beryl/scripts/README.md 'Installed Readiness'
assert_contains .beryl/scripts/README.md 'check.sh --development'
assert_contains .beryl/scripts/README.md 'core.hooksPath'
assert_contains .beryl/scripts/README.md 'ready-with-preserved-external-contracts'
assert_contains .beryl/scripts/README.md 'Beryl does not enforce'
assert_contains .beryl/scripts/README.md 'run-lifecycle-tests.sh'
assert_contains README.md 'lifecycle-regressions'
assert_contains .github/workflows/deterministic-checks.yml 'run-lifecycle-tests.sh'
assert_contains .beryl/scripts/README.md 'sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile minimal'
assert_contains .beryl/scripts/README.md 'sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --components driver'
assert_contains .beryl/scripts/README.md 'sh beryl-install.sh --uninstall --ref "$BERYL_REF"'
assert_contains .beryl/scripts/README.md '--expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile full'
assert_contains .beryl/agent/adr/0010-unified-transactional-install-lifecycle.md 'implemented lifecycle architecture'
assert_contains .beryl/agent/adr/0010-unified-transactional-install-lifecycle.md 'candidate lock'
assert_contains .beryl/agent/adr/0010-unified-transactional-install-lifecycle.md 'expectedSourceSha256'
assert_contains .beryl/agent/architecture.md 'standalone `--bootstrap-agent`'
assert_contains .beryl/agent/ubiquitous-language.md 'Recovery Lifecycle'
assert_contains .beryl/agent/ubiquitous-language.md 'Readiness State'
assert_contains .beryl/agent/ubiquitous-language.md 'Not destructive authority'
assert_contains RELEASING.md 'beryl-release-metadata-v1'
assert_contains RELEASING.md 'sign-release-metadata.sh'
assert_contains RELEASING.md 'private key'
assert_contains RELEASING.md 'independently trusted bootstrap channel'
assert_contains .github/workflows/release-checksums.yml 'contents: write'
assert_contains .github/workflows/release-checksums.yml 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
assert_contains .github/workflows/release-checksums.yml 'ref: ${{ steps.release.outputs.sha }}'
assert_contains .github/workflows/release-checksums.yml 'https://codeload.github.com/${GITHUB_REPOSITORY}/tar.gz/${RELEASE_SHA}'
assert_contains .github/workflows/release-checksums.yml 'beryl-${RELEASE_SHA}.tar.gz'
assert_help_contains 'full 40-character commit'
assert_help_contains 'Required for every remote lifecycle archive'
assert_help_contains 'local Beryl Git checkout'
assert_help_contains 'explicitly selected, unchanged'
assert_help_contains 'historical profile/components authorization'
assert_help_contains 'component surface before removing newer files'

if rg -n -- '--previous-source-dir' \
  "${REPO_ROOT}/README.md" \
  "${REPO_ROOT}/Quickstart.md" \
  "${REPO_ROOT}/Cheatsheet.md" \
  "${REPO_ROOT}/RELEASING.md" \
  "${REPO_ROOT}/.beryl/scripts/README.md" \
  "${REPO_ROOT}/.beryl/agent/skills/using-beryl/SKILL.md" \
  "${REPO_ROOT}/.beryl/agent/architecture.md" \
  "${REPO_ROOT}/.beryl/agent/design-tree.md" \
  "${REPO_ROOT}/.beryl/agent/ubiquitous-language.md" \
  "${REPO_ROOT}/.beryl/agent/security-policy.md" \
  "${REPO_ROOT}/.beryl/agent/adr/0010-unified-transactional-install-lifecycle.md"; then
  fail 'documentation or canonical lifecycle contract retains removed previous-source option'
fi

printf 'documentation contract tests passed\n'
