# ADR 0004: Relocate Control Plane Under `.beryl`

## Status

Accepted.

## Context

Beryl is installed into existing repositories. Root-level directories such as `agent/`, `scripts/`, `githooks/`, and `driver/` collide with host project names and make it hard to distinguish Beryl-owned files from project-owned files.

Some files cannot move because external tools look for them at fixed root paths: instruction shims, GitHub workflows, and `.gitignore`.

## Decision

Move Beryl-owned implementation files under `.beryl/`:

- `.beryl/agent/`
- `.beryl/scripts/`
- `.beryl/githooks/`
- `.beryl/driver/`

Keep fixed root contracts at their required locations and repoint them into `.beryl/`.

Scripts must distinguish:

- `BERYL_ROOT`: the `.beryl` implementation root.
- `REPO_ROOT`: the host project root.

## Consequences

Host projects get a smaller collision surface. Beryl scripts can be copied as one subtree, but every script that scans host files or writes root shims must use `REPO_ROOT`, not `BERYL_ROOT`.
