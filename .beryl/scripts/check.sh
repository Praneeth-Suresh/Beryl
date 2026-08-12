#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# Validate the lexical invocation path before resolving directories or
# sourcing paths.sh. This keeps a target's .beryl symlink from redirecting the
# aggregate gate into an external tree.
validate_lexical_path() {
  local path="$1" current="" segment
  local -a segments=()

  [[ "${path}" == /* ]] || fail "invoked script path must be absolute after lexical expansion"
  IFS='/' read -r -a segments <<< "${path#/}"
  for segment in "${segments[@]}"; do
    [[ -n "${segment}" ]] || continue
    case "${segment}" in
      .|..) fail "invoked script path must not contain . or .. segments" ;;
    esac
    current="${current}/${segment}"
    [[ ! -L "${current}" ]] || fail "invoked script path has a symlink ancestor: ${current}"
  done
}

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ "${SCRIPT_PATH}" == ./* ]]; do
  SCRIPT_PATH="${SCRIPT_PATH#./}"
done
if [[ "${SCRIPT_PATH}" == /* ]]; then
  SCRIPT_ABS="${SCRIPT_PATH}"
else
  SCRIPT_ABS="${PWD%/}/${SCRIPT_PATH}"
fi
validate_lexical_path "${SCRIPT_ABS}"
SCRIPT_DIR="${SCRIPT_ABS%/*}"
case "${SCRIPT_DIR}" in
  */.beryl/scripts) BERYL_ROOT="${SCRIPT_DIR%/scripts}" ;;
  *) fail "check.sh must be located at .beryl/scripts/check.sh" ;;
esac
REPO_ROOT="${BERYL_ROOT%/.beryl}"
[[ "${REPO_ROOT}" != "${BERYL_ROOT}" ]] || fail "check.sh must have a .beryl parent"
validate_lexical_path "${BERYL_ROOT}"
validate_lexical_path "${REPO_ROOT}"

DEVELOPMENT_MODE="0"

usage() {
  cat <<'USAGE'
Usage: .beryl/scripts/check.sh [--development]

--development  Run source-checkout-only validation. Requires Beryl's tracked
               .beryl/source-checkout.marker; installed targets use lock-backed
               readiness validation by default.
USAGE
}

development_marker_valid() {
  local marker="${BERYL_ROOT}/source-checkout.marker"
  [[ ! -L "${marker}" ]] || fail ".beryl/source-checkout.marker must not be a symlink"
  [[ -f "${marker}" ]] || fail "--development requires .beryl/source-checkout.marker"
  grep -qxF 'Beryl source checkout marker v1' "${marker}" || \
    fail "invalid .beryl/source-checkout.marker"
}

parse_args() {
  while (($#)); do
    case "$1" in
      --development) DEVELOPMENT_MODE="1" ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown argument: $1" ;;
    esac
    shift
  done
}

parse_args "$@"
if [[ "${DEVELOPMENT_MODE}" == "1" ]]; then
  development_marker_valid
fi

# The doctor validates every selected managed executable and its source/load
# dependencies without following symlinks. It must run before this aggregate
# gate invokes any child check script.
if [[ "${DEVELOPMENT_MODE}" == "1" ]]; then
  "${BERYL_ROOT}/agent/scripts/agent-doctor.sh" --development
else
  "${BERYL_ROOT}/agent/scripts/agent-doctor.sh"
fi

printf "Running deterministic checks...\n"

"${BERYL_ROOT}/scripts/check-md.sh"
"${BERYL_ROOT}/scripts/validate-components.sh"
if [[ "${DEVELOPMENT_MODE}" == "1" ]]; then
  "${BERYL_ROOT}/scripts/check-install-surface.sh"
else
  printf "check-install-surface: installed target (skipping source-surface self-check)\n"
fi
"${BERYL_ROOT}/scripts/check-initial-build-workflow.sh"
"${BERYL_ROOT}/scripts/check-secrets.sh" --selftest
if [[ "${CHECK_AFFECTED_MODE:-worktree}" == "staged" ]]; then
  "${BERYL_ROOT}/scripts/check-secrets.sh" --staged
else
  "${BERYL_ROOT}/scripts/check-secrets.sh" --worktree
fi
"${BERYL_ROOT}/scripts/check-tests-unchanged.sh"
"${BERYL_ROOT}/scripts/check-project.sh"

printf "OK\n"
