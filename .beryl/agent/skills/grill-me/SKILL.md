# Grill Me (Alias)

## Purpose

Run a pre-flight design critique before non-trivial implementation.

## Trigger Conditions

- Non-trivial feature work
- Architecture or boundary changes
- Cross-context changes
- Ambiguous bug fixes
- Security-sensitive behavior

## Input Contract (required)

```yaml
skill: grill-me
requested_outcome: "<one paragraph>"
bounded_context: "<single context name>"
candidate_public_interface: "<API or boundary to change>"
constraints:
  security: "<constraint or none>"
  reliability: "<constraint or none>"
  scalability: "<constraint or none>"
  delivery: "<constraint or none>"
```

## Process

1. Restate the requested outcome.
2. Identify bounded context and public interface.
3. List viable options.
4. Critique each option for reliability, context management, security, scalability, testability, and coupling.
5. Ask: "What assumption would make this wrong?"
6. Select an approach and define the first internal implementation step.

## Output Template (required)

```yaml
skill: grill-me
status: success
chosen_approach: "<decision>"
rejected_alternatives:
  - option: "<name>"
    reason: "<why rejected>"
main_risks:
  - "<risk>"
assumption_that_can_break_plan: "<assumption>"
first_internal_step: "<smallest end-to-end behavior>"
checks_to_run:
  narrow: ["<command>"]
  broad: ["<command>"]
likely_files_to_change:
  - "<path>"
design_updates:
  update_design_tree: true
  update_architecture: false
  create_or_update_adr: false
notes: "<short rationale>"
```

## Success Criteria

- Output uses the exact template keys.
- At least one rejected alternative is recorded.
- First internal step and checks are concrete and executable.
- Design update decisions are explicit booleans.

## Refusal / Abort Conditions

Return this template when aborting:

```yaml
skill: grill-me
status: abort
reason_code: "<missing-input|cross-context-unclear|security-constraint-unknown>"
missing_or_blocked:
  - "<item>"
required_user_input: "<single next clarification>"
```

Abort if:

- `requested_outcome`, `bounded_context`, or `candidate_public_interface` is missing.
- The change spans multiple contexts without clear ownership.
- Security/reliability constraints are unknown for a security-sensitive change.

## File Update Permissions

- May update: `.beryl/agent/design-tree.md`, `.beryl/agent/architecture.md`, `.beryl/agent/ubiquitous-language.md`, `.beryl/agent/adr/*`
- Must not edit implementation code directly as part of this skill output phase
