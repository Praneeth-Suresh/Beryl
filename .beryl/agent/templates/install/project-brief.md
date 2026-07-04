# Project Brief

## Product Goal

Build **[application]** for **[primary users]** so they can **[core outcome]**.

## Primary Workflows

1. **[Workflow name]**: [user goal and success condition]
2. **[Workflow name]**: [user goal and success condition]
3. **[Workflow name]**: [user goal and success condition]

## Non-Goals

- [Explicitly out of scope now]
- [Explicitly out of scope now]

## External Systems

| System | Why it exists | Interface owner | Failure fallback |
| --- | --- | --- | --- |
| [Service/API/DB] | [Need] | [Context/adapter] | [Behavior on failure] |

## Definition Of Done

A feature is complete only when it has all of the following:

1. A small design artifact update (`design-tree.md` and/or ADR) when design changes.
2. Clear boundary types/interfaces (where language supports this).
3. Behavior tests plus at least one edge case test.
4. Deterministic checks run (`./.beryl/scripts/check.sh` and relevant project checks).
5. No new illegal boundary crossings.
