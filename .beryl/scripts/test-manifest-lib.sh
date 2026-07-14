#!/usr/bin/env bash

tm_fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

tm_detect_hash_cmd() {
  if command -v sha256sum >/dev/null 2>&1; then
    TM_HASH_CMD=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    TM_HASH_CMD=(shasum -a 256)
  else
    tm_fail "need sha256sum or shasum."
  fi
}

tm_hash_only() {
  local file="$1"
  local out
  out="$("${TM_HASH_CMD[@]}" "$file")"
  printf "%s" "${out%% *}"
}

tm_match_any() {
  local value="$1"
  shift
  local pattern
  for pattern in "$@"; do
    [[ "$value" == $pattern ]] && return 0
  done
  return 1
}

tm_load_manifest_config() {
  local root_dir="$1"
  local beryl_root="${2:-${root_dir}/.beryl}"
  local config_path="${beryl_root}/agent/test-manifest.conf"

  MANIFEST_PATH=""
  INCLUDE_GLOBS=()
  EXCLUDE_GLOBS=()

  # shellcheck source=safe-conf.sh
  source "${beryl_root}/scripts/safe-conf.sh"
  # Parsed as data, never sourced (see safe-conf.sh).
  sc_load_conf "${config_path}" MANIFEST_PATH INCLUDE_GLOBS EXCLUDE_GLOBS

  if [[ -z "${MANIFEST_PATH}" ]]; then
    MANIFEST_PATH="tests/.manifest.sha256"
  fi

  if ((${#INCLUDE_GLOBS[@]} == 0)); then
    INCLUDE_GLOBS=(
      "tests/**"
      "spec/**"
      "src/**/__tests__/**"
      "**/*.test.*"
      "**/*.spec.*"
      "**/*_test.go"
      "**/*_test.py"
    )
  fi

  if [[ "${MANIFEST_PATH}" = /* ]]; then
    tm_fail "MANIFEST_PATH must be repository-relative: ${MANIFEST_PATH}"
  fi

  TM_MANIFEST_REL="${MANIFEST_PATH#./}"
  TM_MANIFEST_ABS="${root_dir}/${TM_MANIFEST_REL}"
}

tm_collect_manifest_files() {
  local root_dir="$1"
  local rel
  local collected=""

  while IFS= read -r -d '' path; do
    rel="${path#${root_dir}/}"
    [[ "${rel}" == "${TM_MANIFEST_REL}" ]] && continue

    if ! tm_match_any "${rel}" "${INCLUDE_GLOBS[@]}"; then
      continue
    fi

    if ((${#EXCLUDE_GLOBS[@]} > 0)) && tm_match_any "${rel}" "${EXCLUDE_GLOBS[@]}"; then
      continue
    fi

    collected="${collected}
${rel}"
  done < <(find "${root_dir}" -type f -not -path "${root_dir}/.git/*" -print0)

  printf "%s\n" "${collected}" | sed '/^$/d' | LC_ALL=C sort -u
}

tm_normalize_manifest() {
  local file="$1"
  awk '{sub(/\r$/, ""); h=$1; $1=""; sub(/^ +/, ""); print h"  "$0}' "$file"
}
