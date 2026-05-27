# Agent Control Plane

This directory is the canonical source of truth for agent behavior in this repository.

## Why this exists

The system follows the core rule from `Plan.md`: generation speed is useful only when deterministic feedback loops are stronger than the generation loop. These files make that rule executable.

## Source of truth model

1. `agent/` files are canonical.
2. Tool-specific instruction files (`AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`, `.codex/AGENTS.md`) are generated shims.
3. Do not edit generated shims manually. Edit `agent/tool-instruction-template.md` and run:

```bash
./agent/scripts/sync-agent-env.sh
```

## Bootstrap checklist

Fill these files before feature implementation:

- `project-brief.md`
- `ubiquitous-language.md`
- `design-tree.md`
- `architecture.md`
- `testing-policy.md`
- `agent-rules.md`
- `task-routing.md`

Then run:

```bash
./agent/scripts/sync-agent-env.sh
./agent/scripts/agent-doctor.sh
./scripts/check.sh
```

## Test manifest scope

Configure test immutability detection in `agent/test-manifest.conf`.

- `INCLUDE_GLOBS`: which test files are tracked
- `EXCLUDE_GLOBS`: ignored paths
- `MANIFEST_PATH`: where the hash manifest is stored

## Decision recording rule

- Use `design-tree.md` for evolving or unresolved design choices.
- Use `agent/adr/` when a decision changes durable architecture, boundaries, terminology, data shape, or test strategy.

## Skill naming alias

- `grill-me` is the shorthand alias.
- `grill-me` is the canonical skill contract.
- `interview-me` is the user-interview fallback for unresolved `grill-me` decisions.

## Task routing

- `task-routing.md` maps the user's current intent to one workflow skill.
- Load one task workflow first: `planning`, `adding-features`, `debugging`, or `explaining-codebase`.
- Feature implementation requires a user-ratified plan. If no approved plan exists, plan first and stop.
- Feature-slice bookkeeping is internal and temporary. Use ignored `session-state.md` only when needed for resume.
- Use sub-agents only when the user explicitly asks for them.
- Keep debugging error history session-scoped and bounded in `session-state.md`.

## Context hygiene

- Keep temporary implementation state out of canonical files.
- Clear `agent/session-state.md` after a feature is complete.
- Promote only durable decisions to `design-tree.md`, `architecture.md`, `ubiquitous-language.md`, or `adr/`.
