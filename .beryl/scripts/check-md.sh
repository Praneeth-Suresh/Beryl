#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# Deterministic, dependency-free Markdown sanity checks:
# - no unclosed backtick or tilde code fences
# - no TAB characters
# Applies to all markdown files in the repository except .git.

md_fence_marker=""
md_fence_length=0
md_fence_trailing=""

# Extract a Markdown fence that begins after at most three spaces. The caller
# receives the fence marker, length, and trailing text through the globals
# above. Markdown permits closing fences that are longer than their opener,
# but not a different marker or a shorter run.
md_parse_fence() {
  local line="$1"
  local offset=0 marker length=0

  while [[ "${offset}" -lt "${#line}" && "${line:${offset}:1}" == " " ]]; do
    offset=$((offset + 1))
  done
  (( offset <= 3 )) || return 1

  marker="${line:${offset}:1}"
  [[ "${marker}" == '`' || "${marker}" == '~' ]] || return 1

  while [[ "${line:$((offset + length)):1}" == "${marker}" ]]; do
    length=$((length + 1))
  done
  (( length >= 3 )) || return 1

  md_fence_marker="${marker}"
  md_fence_length="${length}"
  md_fence_trailing="${line:$((offset + length))}"
}

md_files="$(cd "${REPO_ROOT}" && find . -type f -name '*.md' -not -path './.git/*' | LC_ALL=C sort)"

if [[ -z "${md_files}" ]]; then
  printf "check-md: no markdown files found (skipping)\n"
  exit 0
fi

count=0
while IFS= read -r f; do
  [[ -n "${f}" ]] || continue
  count=$((count + 1))
  path="${REPO_ROOT}/${f#./}"

  open_marker=""
  open_length=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if ! md_parse_fence "${line}"; then
      continue
    fi

    if [[ -z "${open_marker}" ]]; then
      open_marker="${md_fence_marker}"
      open_length="${md_fence_length}"
      continue
    fi

    if [[ "${md_fence_marker}" == "${open_marker}" &&
      "${md_fence_length}" -ge "${open_length}" &&
      "${md_fence_trailing}" =~ ^[[:space:]]*$ ]]; then
      open_marker=""
      open_length=0
    fi
  done <"${path}"

  if [[ -n "${open_marker}" ]]; then
    fail "check-md: Unclosed ${open_marker} code fence in ${f#./} (opened with ${open_length} markers)."
  fi

  # Tabs in Markdown tend to render inconsistently across viewers.
  if LC_ALL=C grep -n $'\t' "${path}" >/dev/null 2>&1; then
    fail "check-md: Tab character found in ${f#./}."
  fi
done <<EOF
${md_files}
EOF

printf "check-md: OK (%d files)\n" "${count}"
