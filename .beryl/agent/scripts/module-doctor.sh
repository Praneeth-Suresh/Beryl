#!/usr/bin/env bash
set -euo pipefail

# Finds all sub-module agent/ directories and validates their required files.
# Usage: ./.beryl/agent/scripts/module-doctor.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/paths.sh
if [[ -f "${SCRIPT_DIR}/../../scripts/paths.sh" ]]; then
  source "${SCRIPT_DIR}/../../scripts/paths.sh"
else
  BERYL_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
  if command -v git >/dev/null 2>&1 && git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel >/dev/null 2>&1; then
    REPO_ROOT="$(git -C "${BERYL_ROOT}/.." rev-parse --show-toplevel)"
  else
    REPO_ROOT="$(cd "${BERYL_ROOT}/.." && pwd)"
  fi
fi

fail() { printf "ERROR: %s\n" "$*" >&2; ERRORS=$((ERRORS + 1)); }

ERRORS=0
MODULES=0

# Find module-level agent dirs (any agent/ that is NOT the root .beryl/agent/)
while IFS= read -r -d '' module_agent; do
  module_dir="$(dirname "$module_agent")"
  rel="${module_dir#${REPO_ROOT}/}"
  MODULES=$((MODULES + 1))

  printf "Checking module: %s\n" "$rel"

  required=(
    "module-context.md"
    "project-brief.md"
    "design-tree.md"
    "architecture.md"
    "ubiquitous-language.md"
    "testing-policy.md"
  )

  for file in "${required[@]}"; do
    [[ -f "${module_agent}/${file}" ]] || fail "${rel}/agent/${file} missing"
  done

done < <(find "$REPO_ROOT" -path "$BERYL_ROOT/agent" -prune -o -path "*/node_modules" -prune -o -path "*/.git" -prune -o -type d -name "agent" -print0 2>/dev/null | grep -z -v "^${BERYL_ROOT}/agent$" || true)

if [[ $MODULES -eq 0 ]]; then
  printf "No sub-module agent/ directories found.\n"
  exit 0
fi

if [[ $MODULES -gt 0 && $MODULES -lt 3 ]]; then
  printf "WARNING: Only %d module agent(s) found. Sub-module agents are intended for projects with 3+ complex bounded contexts. Consider whether the root .beryl/agent/ is sufficient.\n" "$MODULES" >&2
fi

if [[ $ERRORS -gt 0 ]]; then
  printf "\n%d error(s) in %d module(s).\n" "$ERRORS" "$MODULES" >&2
  exit 1
fi

printf "\nAll %d module(s) healthy.\n" "$MODULES"
