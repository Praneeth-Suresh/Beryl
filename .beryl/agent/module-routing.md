# Module Agent Routing

## Enforcement Policy

Sub-module agent structures are prohibited unless the project has 3+ bounded contexts declared in root `.beryl/agent/architecture.md`. The `init-module-agent.sh` script enforces this gate automatically. For projects with fewer than 3 bounded contexts, use the root `.beryl/agent/` only — sub-module agents waste context without adding value.

## When Working Inside A Sub-Module

If the file being changed lives under a directory that contains its own `agent/` folder, that module's agent files take precedence for module-specific concerns.

### Loading Order

1. Read the module's `agent/module-context.md` to understand scope and precedence.
2. Load the module's `agent/project-brief.md`, `agent/design-tree.md`, `agent/architecture.md`, `agent/ubiquitous-language.md`, and `agent/testing-policy.md`.
3. For skills, rules, scripts, and security policy: use the root `.beryl/agent/` (these are not duplicated per module).
4. For shared domain terms: check both root and module `ubiquitous-language.md`.

### Cross-Module Work

When a task touches multiple modules:

1. Identify which modules are affected.
2. Load each module's `agent/module-context.md`.
3. Changes to a module's internals follow that module's agent files.
4. Changes to the interface between modules follow root `.beryl/agent/architecture.md`.
5. New shared terms go in root `.beryl/agent/ubiquitous-language.md`.
6. Cross-module boundary changes require a root-level ADR.

### Module Check Commands

Run the module's own check command (from its `agent/testing-policy.md`) for narrow checks, then the root `./.beryl/scripts/check.sh` for the full gate.
