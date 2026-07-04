#!/usr/bin/env bash
set -euo pipefail

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
SINCE="${1:-12.month}"

cd "${REPO_ROOT}"

git log --format=format: --name-only --since="${SINCE}" \
  | sed '/^$/d' \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -20
