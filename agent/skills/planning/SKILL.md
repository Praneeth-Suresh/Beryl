# Planning

## Purpose

Turn a requested change into a small, reviewable plan before implementation.

## Use When

- The user asks for a plan, design, approach, or breakdown.
- A feature request has no approved implementation plan yet.
- The change is non-trivial, cross-context, security-sensitive, or architecturally ambiguous.

## Process

1. Restate the requested outcome.
2. Load only the canonical files needed to understand the relevant bounded context.
3. Identify the public interface, likely files, tests/checks, and design artifacts that may change.
4. Split implementation into internal feature slices when more than one safe implementation step is involved.
5. For risky or ambiguous work, run `grill-me` locally and fold the critique into the plan.
6. Run `interview-me` only if `grill-me` leaves an unresolved user-judgment question that cannot be answered from the repo.
7. Present the user-facing plan and wait for user ratification before implementation.

## Internal State

- Do not ask the user to manage feature slices.
- Do not put temporary feature-slice state in `agent/design-tree.md`.
- If interruption or resume support is needed, write the smallest internal checklist to `agent/session-state.md`.
- `agent/session-state.md` is session-specific and gitignored.
- Remove or clear `agent/session-state.md` when the feature is complete.
- Move only durable decisions into `agent/design-tree.md`, `agent/architecture.md`, `agent/ubiquitous-language.md`, or `agent/adr/*`.

## Output

- Requested outcome
- Bounded context
- Proposed approach
- Implementation approach, summarized without slice IDs
- Tests/checks to run
- Design files or ADRs likely to change
- Open questions or assumptions

## Stop Condition

When this workflow is used as the planning gate for feature implementation, stop after presenting the plan. Do not edit code until the user ratifies the plan.
