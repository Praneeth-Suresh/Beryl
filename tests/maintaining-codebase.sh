#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${REPO_ROOT}/.beryl/agent/skills/maintaining-codebase/SKILL.md"

require() {
  grep -Fq -- "$2" "$1" || { printf 'missing required skill contract: %s\n' "$2" >&2; exit 1; }
}

require "$skill" 'evidence-led'
require "$skill" 'repository-wide improvement program'
require "$skill" '`tracking-entropy` remains the focused hotspot-analysis skill'
require "$skill" 'State unavailable evidence and do not invent it.'
require "$skill" 'owning bounded context'
require "$skill" 'dependency-ordered, behavior-preserving'
require "$skill" 'Do not modify code during the assessment.'
require "$skill" 'Present the program and wait for'
require "$skill" 'Never bundle unrelated cleanup'
require "$skill" 'approval_required_before_implementation: true'
grep -Fq '.beryl/agent/skills/maintaining-codebase/SKILL.md' "${REPO_ROOT}/.beryl/agent/task-routing.md"

printf 'maintaining-codebase tests passed\n'
