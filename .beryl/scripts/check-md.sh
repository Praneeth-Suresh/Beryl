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
# - no unclosed triple-backtick code fences
# - no TAB characters
# Applies to all markdown files in the repository except .git.

mapfile -t md_files < <(
  cd "${REPO_ROOT}" && find . -type f -name '*.md' -not -path './.git/*' | LC_ALL=C sort
)

if ((${#md_files[@]} == 0)); then
  printf "check-md: no markdown files found (skipping)\n"
  exit 0
fi

for f in "${md_files[@]}"; do
  path="${REPO_ROOT}/${f#./}"

  # Unclosed code fences: count of ``` lines should be even.
  # This is intentionally simple and deterministic.
  fence_count="$(awk '/^```/{c++} END{print c+0}' "${path}")"
  if (( fence_count % 2 != 0 )); then
    fail "check-md: Unclosed code fence in ${f#./} (found ${fence_count} fences)."
  fi

  # Tabs in Markdown tend to render inconsistently across viewers.
  if LC_ALL=C grep -n $'\t' "${path}" >/dev/null 2>&1; then
    fail "check-md: Tab character found in ${f#./}."
  fi
done

printf "check-md: OK (%d files)\n" "${#md_files[@]}"
