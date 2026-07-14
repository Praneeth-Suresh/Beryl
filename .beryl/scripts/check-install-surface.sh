#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
# shellcheck source=beryl-components.sh
source "${SCRIPT_DIR}/beryl-components.sh"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

split_csv() {
  printf "%s\n" "${1}" | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d'
}

manifest_expected_paths() {
  local mode="$1"
  local value="$2"
  local requested=""
  local resolved=""

  case "${mode}" in
    profile)
      requested="$(bc_profile_components "${REPO_ROOT}/.beryl/beryl.components.json" "${value}")"
      ;;
    components)
      requested="$(split_csv "${value}")"
      ;;
    *)
      fail "unknown manifest mode: ${mode}"
      ;;
  esac

  resolved="$(bc_resolve_components "${REPO_ROOT}/.beryl/beryl.components.json" ${requested})"

  for component in ${resolved}; do
    bc_component_field "${REPO_ROOT}/.beryl/beryl.components.json" "${component}" paths
    bc_component_field "${REPO_ROOT}/.beryl/beryl.components.json" "${component}" rootPaths
  done | sed '/^$/d' | awk '!seen[$0]++'
}

install_dry_run_paths() {
  local mode="$1"
  local value="$2"
  local output=""
  local -a args

  output="$(mktemp)"
  trap 'rm -f "$output"' RETURN

  if [ "${mode}" = "profile" ]; then
    args=(--profile "${value}")
  else
    args=(--components "${value}")
  fi

  sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --dry-run "${args[@]}" >"$output"

  awk '
    /^beryl: install paths:/{in_paths=1; next}
    in_paths {
      if ($0 !~ /^  /) exit
      sub(/^  /, "", $0)
      print $0
    }
  ' "$output"
}

expect_no_diff() {
  local label="$1"
  local expected_file="$2"
  local actual_file="$3"

  local missing extra
  missing="$(comm -23 "$expected_file" "$actual_file")"
  extra="$(comm -13 "$expected_file" "$actual_file")"

  if [ -n "${missing}" ] || [ -n "${extra}" ]; then
    if [ -n "${missing}" ]; then
      printf "check-install-surface: %s missing expected paths:\n%s\n" "${label}" "${missing}"
    fi
    if [ -n "${extra}" ]; then
      printf "check-install-surface: %s has unexpected paths:\n%s\n" "${label}" "${extra}"
    fi
    fail "${label} failed."
  fi
}

check_scope() {
  local label="$1"
  local mode="$2"
  local value="$3"
  local expected
  local actual

  printf "check-install-surface: checking %s\n" "${label}"

  expected="$(mktemp)"
  actual="$(mktemp)"
  trap 'rm -f "$expected" "$actual"' RETURN

  install_dry_run_paths "${mode}" "${value}" | sed '/^$/d' | sort -u > "${actual}"

  (
    if [ "${mode}" = "profile" ]; then
      manifest_expected_paths profile "${value}"
    else
      manifest_expected_paths components "${value}"
    fi
  ) | sed '/^$/d' | sort -u > "${expected}"

  expect_no_diff "${label}" "${expected}" "${actual}"
  printf "check-install-surface: %s OK\n" "${label}"
}

printf "check-install-surface: validating install path scope against manifest\n"

if [[ ! -f "${REPO_ROOT}/install.sh" ]]; then
  printf "check-install-surface: install.sh is not present in this installed target (skipping)\n"
  exit 0
fi

check_scope "profile:minimal" "profile" "minimal"
check_scope "profile:standard" "profile" "standard"
check_scope "profile:full" "profile" "full"
check_scope "components:driver" "components" "driver"

printf "check-install-surface: PASS\n"
