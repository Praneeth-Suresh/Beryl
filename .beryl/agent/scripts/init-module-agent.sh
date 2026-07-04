#!/usr/bin/env bash
set -euo pipefail

# Usage: ./.beryl/agent/scripts/init-module-agent.sh <module-path> <module-name> <bounded-context>
# Example: ./.beryl/agent/scripts/init-module-agent.sh modules/billing billing "Plans, invoices, subscription state"

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

fail() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

MODULE_PATH="${1:-}"
MODULE_NAME="${2:-}"
BOUNDED_CONTEXT="${3:-}"

[[ -n "$MODULE_PATH" ]] || fail "Usage: $0 <module-path> <module-name> <bounded-context>"
[[ -n "$MODULE_NAME" ]] || fail "module-name is required"
[[ -n "$BOUNDED_CONTEXT" ]] || fail "bounded-context description is required"

TARGET="${REPO_ROOT}/${MODULE_PATH}"
AGENT_DIR="${TARGET}/agent"

[[ -d "$TARGET" ]] || fail "Module directory does not exist: $MODULE_PATH"
[[ ! -d "$AGENT_DIR" ]] || fail "agent/ already exists in $MODULE_PATH"

# Enforce minimum complexity: require 3+ bounded contexts in root architecture.md
ARCH_FILE="${BERYL_ROOT}/agent/architecture.md"
[[ -f "$ARCH_FILE" ]] || fail "Root .beryl/agent/architecture.md not found. Fill project facts first."
# Count data rows in Bounded Contexts table: table rows minus header and separator rows
TOTAL_ROWS=$(grep -cE '^\|[^|]+\|[^|]+\|[^|]+\|' "$ARCH_FILE" || echo 0)
SEPARATOR_ROWS=$(grep -cE '^\|[[:space:]]*-' "$ARCH_FILE" || echo 0)
# Each table has 1 header + 1 separator; data rows = total - (2 * number of tables)
# Simpler: subtract separators (1 per table) and same count for headers
CONTEXT_COUNT=$((TOTAL_ROWS - SEPARATOR_ROWS * 2))
if [[ $CONTEXT_COUNT -lt 3 ]]; then
  fail "Sub-module agents require 3+ bounded contexts declared in .beryl/agent/architecture.md (found ${CONTEXT_COUNT}). For smaller projects, use the root .beryl/agent/ only."
fi

mkdir -p "$AGENT_DIR/adr"

# module-context.md
sed \
  -e "s|\[module-name\]|${MODULE_NAME}|g" \
  -e "s|\[relative path from repo root\]|${MODULE_PATH}|g" \
  -e "s|\[repo root or parent module path\]|.|g" \
  -e "s|\[which domain context this module owns\]|${BOUNDED_CONTEXT}|g" \
  "${BERYL_ROOT}/agent/templates/module-context.md" > "$AGENT_DIR/module-context.md"

# project-brief.md
cat > "$AGENT_DIR/project-brief.md" << EOF
# Module Brief: ${MODULE_NAME}

## Module Goal

[What this module does for the system.]

## Bounded Context

${BOUNDED_CONTEXT}

## Primary Behaviors

1. [Behavior]

## Non-Goals

- [What this module does NOT own]

## Definition Of Done

- Types/interfaces for new boundaries.
- Tests for intended behavior and at least one edge case.
- Passing module-level checks.
- No imports from sibling module internals.
EOF

# design-tree.md
cat > "$AGENT_DIR/design-tree.md" << EOF
# Design Tree: ${MODULE_NAME}

## Current Design Concept

[One paragraph describing the organizing idea of this module.]

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |

## Settled Decisions

| Decision | Choice | Date | ADR |
| --- | --- | --- | --- |

## Pressure Points

- [None yet]
EOF

# architecture.md
cat > "$AGENT_DIR/architecture.md" << EOF
# Architecture: ${MODULE_NAME}

## Internal Structure

| Layer/Component | Owns | Public Entry Point |
| --- | --- | --- |
| [Component] | [Responsibility] | [Path] |

## Module Public Interface

Sibling modules import only from: [public entry point path]

## Internal Boundary Rules

- [Add as internal structure emerges]

## Adapters

| External System | Adapter Location | Notes |
| --- | --- | --- |
EOF

# ubiquitous-language.md
cat > "$AGENT_DIR/ubiquitous-language.md" << EOF
# Ubiquitous Language: ${MODULE_NAME}

Terms specific to this module. Root-level shared terms are in the root \`.beryl/agent/ubiquitous-language.md\`.

| Business Term | Technical Symbol | Definition | Constraints | Avoid |
| --- | --- | --- | --- | --- |
EOF

# testing-policy.md
cat > "$AGENT_DIR/testing-policy.md" << EOF
# Testing Policy: ${MODULE_NAME}

## Commands

| Check | Command | Notes |
| --- | --- | --- |
| Format (mutating) | [not configured yet] | Run after edits |
| Format (check) | [not configured yet] | Used in CI gate |
| Lint | [not configured yet] | |
| Typecheck | [not configured yet] | |
| Unit tests | [not configured yet] | |
| Integration tests | [not configured yet] | |
| Module check | [not configured yet] | Runs all of the above in order |

## Test Rules

- Existing tests may not be weakened to make implementation pass.
- Mock external systems and sibling modules at the adapter boundary.
- Do not mock internal domain logic.
EOF

printf "Created module agent structure: %s/agent/\n" "$MODULE_PATH"
printf "Next steps:\n"
printf "  1. Fill the generated files with module-specific content.\n"
printf "  2. Add module to root .beryl/agent/architecture.md.\n"
printf "  3. Run ./.beryl/agent/scripts/agent-doctor.sh to verify root is still healthy.\n"
