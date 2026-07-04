# Adding Features

## Purpose

Implement approved feature work one internal feature slice at a time.

## Required Gate

Feature implementation requires an approved plan.

- If no approved plan exists, run the planning workflow first and stop after presenting the plan.
- Do not edit implementation code until the user ratifies the plan.
- After ratification, implement only the next internal feature slice.
- Before coding, state the success checks that will prove the selected slice or redirect worked.
- Before coding, propose commit boundaries for the selected work.

## Success Checks

Before implementation, state:

- Expected file, route, or artifact change.
- Narrow test/check command that should prove the behavior.
- Broader check command, normally `./.beryl/scripts/check.sh`.
- Generated output, build artifact, or browser evidence when applicable.
- One user-visible behavior to verify.

If the approved plan does not contain success checks, define the smallest checks consistent with the approved scope before coding. If defining those checks changes the scope, return to planning and wait for user ratification.

## Commit Boundaries

Before implementation, state intended commit boundaries.

Each commit boundary must:

- Have one purpose.
- List expected files or file groups.
- Include the check command that validates it.
- Avoid mixing generated output, docs, tests, and source unless one boundary genuinely requires them together.

If the approved plan has no commit boundaries, define them before coding. If a changed file falls outside the boundaries, either stop and ask for approval or flag it clearly in the final response.

## Process

1. Confirm the approved plan or produce one if missing.
2. Load only the relevant canonical files:
   - `.beryl/agent/project-brief.md`
   - `.beryl/agent/design-tree.md`
   - `.beryl/agent/architecture.md`
   - `.beryl/agent/ubiquitous-language.md`
   - `.beryl/agent/testing-policy.md`
   - `.beryl/agent/agent-rules.md`
3. If the feature needs multiple implementation steps or may be interrupted, create or update `.beryl/agent/session-state.md` with the smallest internal feature-slice checklist.
4. Select exactly one internal feature slice before coding.
5. State the success checks for the selected slice.
6. State the commit boundaries for the selected work.
7. Run `testing-vertical-slices` to choose the smallest useful test/check.
8. Implement the selected slice behind the intended public interface.
9. Run the formatter command, narrow checks, then the broader project check.
10. Update `.beryl/agent/session-state.md` only if more work remains or the slice is blocked.
11. Clear `.beryl/agent/session-state.md` when the feature is complete.
12. Update glossary, architecture, design tree, or ADRs only when durable design knowledge changed.

## Rules

- Do not expose feature-slice bookkeeping to the user.
- Do not store session-specific slice state in canonical files.
- Do not start a second slice in the same pass unless the approved plan and checks make it safe.
- Do not weaken tests to make implementation pass.
- If tests change intentionally, update the test manifest and explain why.
- Do not use sub-agents unless the user explicitly asks for them.

## Temporary Vs Durable State

Temporary state belongs in `.beryl/agent/session-state.md` and must be cleared when no longer needed:

- internal feature slices
- current blocked/resume note
- failing command excerpts
- scratch reviewer notes

Durable state belongs in canonical files only when it changes future work:

- bounded context ownership
- public interfaces
- adapter contracts
- domain terminology
- settled architectural tradeoffs
- test strategy

## Final Response

- What was implemented or plan awaiting approval
- Files changed
- Map each changed file to the intended commit boundary
- Flag any changed file that does not belong to a stated commit boundary
- Whether the success checks were met
- Checks run
- Checks skipped or unavailable
- Whether tests changed
- Whether the test manifest changed
- Design files or ADRs updated
- Whether temporary session state was cleared or why it remains
