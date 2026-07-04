# Task 01 — Example Task: UI or Data Alignment

Use this file as an example task brief. Fill in your real goal before running the driver.

## Goal

Make one bounded behavior change so that two related views share a single source of truth.

## Context (current state)

- Area: {{AREA_NAME}}
- User flow: {{USER_FLOW}}
- Frontend entry: `{{FRONTEND_PATH_OR_ROUTE}}`
- Backend/API entry: `{{BACKEND_PATH_OR_API}}`
- Current issue to fix: {{1-2 sentence summary of divergence or bug}}

## Requirements

1. Identify the canonical data contract (inputs, outputs, and transformations) for the selected scope.
2. Update the involved UI components so both viewpoints use the same canonical contract.
3. Ensure they agree on membership, ordering, and contribution values for the same filters.
4. Keep rounding, normalization, and empty states consistent in both views.
5. Preserve existing auth/user scoping and saved configurations.

## Acceptance / Playwright checks

1. Reproduce the current mismatch in the target flow.
2. Drive the relevant inputs (selectors, filters, weight/config changes) and assert both views now show matching article/data sets.
3. Assert the same weights/values are used in all dependent render paths.
4. Apply one saved/alternate config and verify both views update together.
5. Validate empty/no-data behavior is the same in both places.

## Out of scope

- Full page redesign.
- Introducing new domains, categories, or new product features.
- Changing unrelated routing or navigation systems.
