#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
# shellcheck source=beryl-components.sh
source "${SCRIPT_DIR}/beryl-components.sh"

manifest="${1:-${BERYL_ROOT}/beryl.components.json}"
bc_validate_manifest "${manifest}"
printf "components: OK (%s)\n" "${manifest#${REPO_ROOT}/}"
