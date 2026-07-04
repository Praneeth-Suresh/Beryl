# Module Context

## Module Identity

- **Name**: [module-name]
- **Path**: [relative path from repo root]
- **Parent**: [repo root or parent module path]
- **Bounded Context**: [which domain context this module owns]

## Precedence

1. Explicit user instructions for the current task.
2. This module's `agent/` files.
3. Root `.beryl/agent/` files (inherited rules, shared language, global architecture).
4. Existing code, tests, and local conventions.

If a module-level file conflicts with root, the module-level file wins for work inside this module.

## Inherited From Root

These root files apply unless this module overrides them:

- `.beryl/agent/agent-rules.md` (engineering rules)
- `.beryl/agent/security-policy.md` (secrets, access limits)
- `.beryl/agent/skills/` (all skills)
- `.beryl/agent/scripts/` (all scripts)

## Module-Specific

These files are authoritative for this module:

- `agent/project-brief.md` (module goal, not whole-project goal)
- `agent/design-tree.md` (module-level decisions)
- `agent/architecture.md` (internal boundaries within this module)
- `agent/ubiquitous-language.md` (module-local terms, supplements root)
- `agent/testing-policy.md` (module-specific commands)

## Cross-Module Rules

- Do not import internals from sibling modules.
- Use only the sibling's declared public entry point.
- New shared terms go in root `.beryl/agent/ubiquitous-language.md`.
- Boundary changes between modules require a root-level ADR.
