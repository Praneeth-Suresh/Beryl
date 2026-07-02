# Agent Rules

## Before Coding

1. Read `agent/task-routing.md`, classify the task, and load only the matching workflow skill.
2. Read the minimum relevant canonical files in `agent/` requested by that workflow.
3. Identify the bounded context and intended public interface.
4. For feature implementation, confirm a user-ratified plan exists. If not, plan first and stop.
5. For non-trivial or ambiguous work, run `grill-me` locally.
6. Run `interview-me` only when `grill-me` leaves an unresolved user-judgment question.
7. Choose the smallest deterministic check that can prove behavior.
8. State success checks before any meaningful redirect or implementation.
9. Use `agent/session-state.md` only for temporary, session-specific implementation state.
10. Do not create sub-module agent structures unless the project has 3+ independently complex bounded contexts declared in root `agent/architecture.md` (in which case, read through `agent/guides/sub-module-agents.md` for more details). For smaller projects, the root `agent/` is sufficient and sub-modules waste context.

## While Coding

1. Work in one internal feature slice at a time.
2. Prefer existing patterns over new abstractions.
3. Define types/interfaces before implementation where possible.
4. Keep public interfaces small; hide detail behind boundaries.
5. Do not reach into another bounded context's internals.
6. Do not weaken tests to pass implementation.
7. For web app or HTML/CSS tasks, use Microsoft Playwright MCP for browser verification instead of screenshot-only assumptions.
8. Do not use sub-agents unless the user explicitly asks for them.
9. Do not expose feature-slice bookkeeping to the user.

## Post-Run Cleanup Review

After a long product run, if the user asks for cleanup or extraction review:

1. Do not implement new features.
2. Read the changed files before recommending cleanup.
3. Identify dead selectors, repeated CSS patterns, rendering functions that should be split, generated artifacts that should not be hand-edited, and tests missing for known regressions.
4. Return one safe extraction slice only.
5. Include the protecting check or missing regression test that should make the extraction safe.

## Before Finishing

1. Run `./scripts/check.sh`.
2. Run any task-specific checks defined in `agent/testing-policy.md`.
3. Update glossary/design tree/architecture/ADRs if durable design changed.
4. Clear `agent/session-state.md` when temporary implementation state is no longer needed.
5. Clear resolved session error history after debugging succeeds.

## Final Response Contract

Final response must include:

- What changed.
- Which checks ran.
- Which checks were skipped or unavailable.
- Whether tests changed.
- Whether `tests/.manifest.sha256` changed.
- Which skill(s) were used.
- Whether temporary session state was cleared or why it remains.
