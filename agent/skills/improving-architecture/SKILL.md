# Improving Architecture

## Purpose

Reduce coupling and context sprawl by improving module boundaries.

## Trigger Conditions

- A feature touches too many unrelated files
- Ownership or module boundaries are unclear
- Repeated illegal or fragile cross-context imports
- Shallow pass-through modules
- Post-run extraction slice needs a clearer boundary before implementation

## Input Contract (required)

```yaml
skill: improving-architecture
friction_point: "<what is hard to change and why>"
bounded_context: "<primary context>"
current_boundary: "<current public interface summary>"
imports_or_dependencies:
  - "<path or dependency>"
existing_boundary_tests:
  - "<path or none>"
```

## Process

1. Identify hidden domain concept at the friction point.
2. Detect shallow modules and pass-through APIs.
3. Propose a smaller, clearer public boundary.
4. Move details behind that boundary.
5. Add or update boundary-protecting tests.
6. Record durable decision in ADR when needed.

For post-run extraction work, do not add new features. Keep the proposal to one behavior-preserving extraction slice and name the check or regression test that protects it.

## Output Template (required)

```yaml
skill: improving-architecture
status: success
current_problem: "<problem statement>"
proposed_boundary: "<new boundary statement>"
public_api_after_change:
  - "<exported function/type>"
internal_files_hidden_behind_boundary:
  - "<path>"
boundary_tests:
  add_or_update:
    - "<path>"
adr_required: false
adr_reason: "<why yes/no>"
narrow_checks_first:
  - "<command>"
broader_checks_after:
  - "<command>"
notes: "<short rationale>"
```

## Success Criteria

- Output uses the exact template keys.
- Public API is explicitly smaller or clearer than before.
- Boundary tests are identified.
- ADR decision is explicit with reason.

## Refusal / Abort Conditions

Return this template when aborting:

```yaml
skill: improving-architecture
status: abort
reason_code: "<ownership-unclear|boundary-not-identifiable|unsafe-refactor-scope>"
missing_or_blocked:
  - "<item>"
required_user_input: "<single next clarification>"
```

Abort if:

- Ownership is unclear across contexts.
- No coherent boundary can be identified from current code.
- Requested refactor scope is too broad for one internal implementation step and cannot be split safely.

## File Update Permissions

- May update: implementation files, `agent/architecture.md`, `agent/design-tree.md`, `agent/adr/*`
- Must keep changes scoped to one internal implementation step per iteration
