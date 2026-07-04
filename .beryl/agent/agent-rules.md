# Agent Rules

## Always-On Operating Defaults

These defaults apply in every agent session even when the user does not restate them. Users only need to mention a default when opting out of or overriding it for the current prompt, such as explicitly allowing sub-agents.

1. Route work through `.beryl/agent/task-routing.md` and the matching workflow skill before editing.
2. Treat ratified feature implementation as `adding-features` work by default.
3. Use `.beryl/agent/session-state.md` only as internal temporary state when needed.
4. After edits, run the formatter command if configured, then narrow checks, then `./.beryl/scripts/check.sh`.
5. Clear temporary session state when the feature, repair, or debugging thread is complete.
6. Never weaken tests to make implementation pass.
7. If tests change intentionally, run `./.beryl/scripts/update-test-manifest.sh` and explain why the test and manifest changes were required.
8. Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

## Before Coding

1. Read `.beryl/agent/task-routing.md`, classify the task, and load only the matching workflow skill.
2. Read the minimum relevant canonical files in `.beryl/agent/` requested by that workflow.
3. Identify the bounded context and intended public interface.
4. For feature implementation, confirm a user-ratified plan exists. If not, plan first and stop.
5. For non-trivial or ambiguous work, run `grill-me` locally.
6. Run `interview-me` only when `grill-me` leaves an unresolved user-judgment question.
7. Choose the smallest deterministic check that can prove behavior.
8. State success checks before any meaningful redirect or implementation.
9. State commit boundaries before implementation.
10. If multiple implementation paths exist, present options and wait for user approval unless the user explicitly allowed the agent to choose.
11. Use `.beryl/agent/session-state.md` only for temporary, session-specific implementation state.
12. Do not create sub-module agent structures unless the project has 3+ independently complex bounded contexts declared in root `.beryl/agent/architecture.md` (in which case, read through `.beryl/agent/guides/sub-module-agents.md` for more details). For smaller projects, the root `.beryl/agent/` is sufficient and sub-modules waste context.

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

## Deletion And Consolidation Safeguard

Before deleting or consolidating root planning or documentation files:

1. List every file to delete or consolidate.
2. State what information is preserved.
3. State what information is lost.
4. State where replacement content will live.
5. Wait for explicit user approval before editing those files.

## Post-Run Cleanup Review

After a long product run, if the user asks for cleanup or extraction review:

1. Do not implement new features.
2. Read the changed files before recommending cleanup.
3. Identify dead selectors, repeated CSS patterns, rendering functions that should be split, generated artifacts that should not be hand-edited, and tests missing for known regressions.
4. Return one safe extraction slice only.
5. Include the protecting check or missing regression test that should make the extraction safe.

## Before Finishing

1. Run the formatter command if configured.
2. Run narrow checks and any task-specific checks defined in `.beryl/agent/testing-policy.md`.
3. Run `./.beryl/scripts/check.sh`.
4. Update glossary/design tree/architecture/ADRs if durable design changed.
5. Clear `.beryl/agent/session-state.md` when temporary implementation state is no longer needed.
6. Clear resolved session error history after debugging succeeds.

## Final Response Contract

Final response must include:

- What changed.
- Map each changed file to the intended commit boundary.
- Flag any changed file that does not belong to a stated commit boundary.
- Which checks ran.
- Which checks were skipped or unavailable.
- Whether tests changed.
- Whether `tests/.manifest.sha256` changed.
- Which skill(s) were used.
- Whether temporary session state was cleared or why it remains.
