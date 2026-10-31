#!/usr/bin/env bash
# Contract test for the simplifying-code skill (issue #44).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill="${REPO_ROOT}/.beryl/agent/skills/simplifying-code/SKILL.md"

require() {
  grep -Fq -- "$2" "$1" || { printf 'missing required skill contract: %s\n' "$2" >&2; exit 1; }
}

[[ -f "${skill}" ]] || { printf 'missing skill: %s\n' "${skill}" >&2; exit 1; }
grep -Eq '^name: simplifying-code$' "${skill}" || { printf 'skill frontmatter name mismatch\n' >&2; exit 1; }

# Complexity is defined by observable symptoms, and findings must cite them.
require "$skill" 'Change amplification'
require "$skill" 'Cognitive load'
require "$skill" 'Unknown unknowns'
require "$skill" 'Every finding must point at one of these.'

# Evidence and local conventions come before judgment.
require "$skill" 'dominant paradigm'
require "$skill" 'Existing conventions win over textbook preferences'
require "$skill" 'Do not invent metrics.'

# Principles cover the main paradigms.
require "$skill" 'Object-oriented code:'
require "$skill" 'Prefer composition over inheritance.'
require "$skill" 'Functional code:'
require "$skill" 'functional core of pure functions'
require "$skill" 'Procedural and scripting code:'
require "$skill" 'Make modules deep'
require "$skill" 'Do not apply a pattern because it is named.'

# Safety gates.
require "$skill" 'Do not change behavior.'
require "$skill" 'Stop and wait for the user to'
require "$skill" 'add it first and confirm it passes'
require "$skill" 'Never weaken a test to make a refactor pass.'
require "$skill" 'Never mix a refactor with a behavior change in the same commit.'

# Routing and hand-off.
grep -Fq '.beryl/agent/skills/simplifying-code/SKILL.md' "${REPO_ROOT}/.beryl/agent/task-routing.md" || \
  { printf 'simplifying-code is not routed\n' >&2; exit 1; }
grep -Fq '`simplifying-code`' "${REPO_ROOT}/.beryl/agent/skills/maintaining-codebase/SKILL.md" || \
  { printf 'maintaining-codebase does not hand slices to simplifying-code\n' >&2; exit 1; }
grep -Fq '`simplifying-code`' "${REPO_ROOT}/AGENTS.md" || \
  { printf 'generated shim does not list simplifying-code\n' >&2; exit 1; }

printf 'simplifying-code tests passed\n'
