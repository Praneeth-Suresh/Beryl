#!/usr/bin/env bash
set -euo pipefail

DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "${DRIVER_DIR}/lib/import_github_issues.py" "$@"
