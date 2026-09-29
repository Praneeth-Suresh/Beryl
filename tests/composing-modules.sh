#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${REPO_ROOT}/.beryl/agent/skills/composing-modules/SKILL.md"

require() {
  grep -Fq -- "$2" "$1" || { printf 'missing required skill contract: %s\n' "$2" >&2; exit 1; }
}

require "$skill" 'at least three independent sources'
require "$skill" 'Registry identity and canonical repository identity match.'
require "$skill" 'no unresolved critical advisory'
require "$skill" 'at least 500 GitHub stars'
require "$skill" 'at least 50 registry dependents, backlinks'
require "$skill" 'past 18 months'
require "$skill" 'at least three'
require "$skill" 'Compare at least two candidates'
require "$skill" 'Request explicit approval'
require "$skill" 'before running a package manager, cloning, changing a manifest or'
grep -Fq '.beryl/agent/skills/composing-modules/SKILL.md' "${REPO_ROOT}/.beryl/agent/task-routing.md"

printf 'composing-modules tests passed\n'
