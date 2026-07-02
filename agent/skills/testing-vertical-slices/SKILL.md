# Testing Vertical Slices

## Purpose

Select and enforce the smallest useful behavior test before implementation.

## Trigger Conditions

- Feature implementation
- Bug fixes with behavior impact
- Refactors that risk boundary behavior

## Input Contract (required)

```yaml
skill: testing-vertical-slices
behavior: "<domain behavior to prove>"
bounded_context: "<single context name>"
existing_tests:
  - "<path or none>"
edge_case: "<most likely failure mode>"
```

## Process

1. Define behavior in domain language.
2. Choose minimal useful test level:
   - Unit for pure rules
   - Integration for adapter/persistence behavior
   - E2E smoke for critical workflow
   - Property-based for invariants
3. Write or identify failing test/check first.
4. Implement only enough to pass.
5. Add one edge-case test.

## Output Template (required)

```yaml
skill: testing-vertical-slices
status: success
chosen_test_level: "<unit|integration|e2e-smoke|property>"
selection_reason: "<why this is minimal and sufficient>"
behavior_under_test: "<single behavior statement>"
edge_case_targeted: "<edge case>"
narrow_checks_first:
  - "<command>"
broader_checks_after:
  - "<command>"
success_checks:
  - "<expected artifact, command, generated output, or user-visible behavior>"
test_files_expected_to_change:
  - "<path or none>"
manifest_update_required: true
notes: "<short rationale>"
```

## Success Criteria

- Output uses the exact template keys.
- Test level is one of the allowed enum values.
- Narrow and broader commands are executable.
- `success_checks` includes at least one artifact or behavior proof and at least one command.
- `manifest_update_required` is accurate when test files change.

## Refusal / Abort Conditions

Return this template when aborting:

```yaml
skill: testing-vertical-slices
status: abort
reason_code: "<behavior-unclear|bounded-context-missing|no-test-surface>"
missing_or_blocked:
  - "<item>"
required_user_input: "<single next clarification>"
```

Abort if:

- Behavior is not specific enough to test.
- Bounded context is not identified.
- No deterministic test/check surface exists and no allowed path to add one is provided.

## File Update Permissions

- May update: test files and test fixtures
- Must update manifest with `./scripts/update-test-manifest.sh` when test files change intentionally
- Must not weaken existing assertions without explicit behavior-change rationale
