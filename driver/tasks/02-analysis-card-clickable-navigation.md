# Task 02 — Example Task: Interaction + Navigation Alignment

Use this file as an example task brief. Fill in your real goal before running the driver.

## Goal

Make interactive behavior consistent across an entire card-like module without breaking existing nested controls.

## Context (current state)

- Area: {{AREA_NAME}}
- Page/component: `{{PAGE_OR_COMPONENT_PATH}}`
- Existing target route/source: `{{TARGET_ROUTE_OR_HANDLER}}`
- Existing click targets: {{CURRENT_CLICKABLES}}
- Nested controls that must keep their own behavior: {{NESTED_CONTROLS}}

## Requirements

1. Make one bounded card/module container navigable without changing unrelated layout.
2. Preserve existing title/button behavior and route destination.
3. Exclude nested controls from container navigation.
4. Keep semantic and accessible markup valid (focus state, accessible name, keyboard support where intended).
5. Keep disabled/unavailable states at their existing behavior while avoiding false affordances.

## Acceptance / Playwright checks

1. Click outside nested controls on each module card and assert it navigates to the expected route.
2. Click title and explicit action elements and assert they navigate to the same route.
3. Interact with each nested control and assert it performs its own action only.
4. Verify focus visibility and keyboard activation behavior for card-level navigation.
5. Verify no invalid nested interactive semantics are introduced.

## Out of scope

- Creating new destinations or pages.
- Changing module data-loading logic.
- Redesigning the entire page container.
