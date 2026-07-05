#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  .beryl/scripts/check-secrets.sh [--worktree|--staged|--selftest]

Modes:
  --worktree  Scan tracked and untracked (non-ignored) files. Default.
  --staged    Scan staged blob contents only. Used by pre-commit.
  --selftest  Prove in a throwaway repo that a staged fake secret is caught.

Deterministic by design: the built-in high-confidence patterns always run,
so results do not depend on optional tooling being installed. Set
BERYL_SECRET_SCANNER=gitleaks to additionally run gitleaks when available.
Lines annotated with beryl:allow-secret are skipped (for documented fakes).
USAGE
}

# High-confidence secret patterns only, to keep the gate deterministic and
# quiet. The private-key prefix is assembled at runtime so this file can never
# match its own pattern text.
build_secret_regex() {
  local begin marker
  begin="-----BEGIN "
  marker="PRIVATE KEY-----"
  SECRET_REGEX="${begin}[A-Z ]*${marker}"
  SECRET_REGEX+="|AKIA[0-9A-Z]{16}"
  SECRET_REGEX+="|gh[pousr]_[A-Za-z0-9]{36,}"
  SECRET_REGEX+="|github_pat_[A-Za-z0-9_]{22,}"
  SECRET_REGEX+="|xox[baprs]-[0-9A-Za-z-]{10,}"
  SECRET_REGEX+="|glpat-[A-Za-z0-9_-]{20,}"
  SECRET_REGEX+="|sk_live_[A-Za-z0-9]{16,}"
  SECRET_REGEX+="|sk-ant-[A-Za-z0-9-]{20,}"
  SECRET_REGEX+="|AIza[0-9A-Za-z_-]{35}"
}

scan_stream() {
  # scan_stream LABEL < content ; prints findings, returns 1 when any found
  local label="$1"
  local hits
  # -e is required: the pattern starts with dashes and would otherwise be
  # parsed as grep options.
  hits="$(grep -I -nE -e "${SECRET_REGEX}" - 2>/dev/null | grep -v 'beryl:allow-secret' || true)"
  if [[ -n "${hits}" ]]; then
    printf "check-secrets: potential secret in %s:\n%s\n" "${label}" "${hits}" >&2
    return 1
  fi
  return 0
}

run_gitleaks_if_requested() {
  [[ "${BERYL_SECRET_SCANNER:-}" == "gitleaks" ]] || return 0
  command -v gitleaks >/dev/null 2>&1 \
    || fail "BERYL_SECRET_SCANNER=gitleaks but gitleaks is not installed"
  if [[ "${mode}" == "staged" ]]; then
    gitleaks protect --staged --no-banner --source "${REPO_ROOT}"
  else
    gitleaks detect --no-git --no-banner --source "${REPO_ROOT}"
  fi
}

scan_worktree() {
  local file found=0
  while IFS= read -r file; do
    [[ -f "${REPO_ROOT}/${file}" ]] || continue
    scan_stream "${file}" < "${REPO_ROOT}/${file}" || found=1
  done < <(
    git -C "${REPO_ROOT}" ls-files
    git -C "${REPO_ROOT}" ls-files --others --exclude-standard
  )
  return "${found}"
}

scan_staged() {
  local file found=0
  while IFS= read -r file; do
    git -C "${REPO_ROOT}" show ":${file}" 2>/dev/null \
      | scan_stream "staged ${file}" || found=1
  done < <(git -C "${REPO_ROOT}" diff --cached --name-only --diff-filter=ACMR)
  return "${found}"
}

selftest() {
  local tmp fake rc
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/beryl-secrets-selftest.XXXXXX")"
  trap 'rm -rf "${tmp}"' RETURN
  git -C "${tmp}" init -q
  # Assembled at runtime so no real-looking token is stored in the repo.
  fake="AKIA$(printf 'ABCD%.0s' 1 2 3 4)"
  printf 'aws_access_key_id = %s\n' "${fake}" > "${tmp}/leak.txt"
  printf 'nothing to see\n' > "${tmp}/clean.txt"
  git -C "${tmp}" add leak.txt clean.txt

  rc=0
  (cd "${tmp}" && REPO_ROOT="${tmp}" scan_staged) >/dev/null 2>&1 || rc=$?
  [[ "${rc}" -ne 0 ]] || fail "selftest: staged fake secret was NOT detected"

  git -C "${tmp}" rm -q --cached leak.txt
  rm -f "${tmp}/leak.txt"
  (cd "${tmp}" && REPO_ROOT="${tmp}" scan_staged) >/dev/null 2>&1 \
    || fail "selftest: clean staged tree was flagged"

  printf "check-secrets: selftest OK (staged fake secret aborts, clean tree passes)\n"
}

mode="worktree"
case "${1:---worktree}" in
  --worktree) mode="worktree" ;;
  --staged) mode="staged" ;;
  --selftest) mode="selftest" ;;
  -h|--help) usage; exit 0 ;;
  *) fail "unknown argument: $1" ;;
esac

build_secret_regex

if [[ "${mode}" == "selftest" ]]; then
  selftest
  exit 0
fi

if ! git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "check-secrets: not a Git repository; nothing to scan (OK)\n"
  exit 0
fi

if [[ "${mode}" == "staged" ]]; then
  scan_staged || fail "staged changes contain potential secrets; commit aborted"
else
  scan_worktree || fail "working tree contains potential secrets"
fi
run_gitleaks_if_requested
printf "check-secrets: OK (%s scan, no secrets found)\n" "${mode}"
