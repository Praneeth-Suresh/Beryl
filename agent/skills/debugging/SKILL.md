# Debugging

## Purpose

Find and fix a failing behavior using evidence from deterministic checks.

## Process

1. Restate the failing behavior and expected behavior.
2. Check `agent/session-state.md` for a current-session error history entry related to this failure.
3. Load only the canonical files needed for the affected bounded context.
4. Reproduce or inspect the failure with the narrowest command available.
5. Record or replace a compact current-session error summary if the failure still exists.
6. Identify the smallest behavior test/check that proves the bug.
7. Run `grill-me` locally if ownership, expected behavior, or boundary impact is ambiguous.
8. Run `interview-me` only if `grill-me` leaves a user-judgment question that cannot be answered from the repo.
9. Apply the smallest fix that addresses the root cause.
10. Run the narrow check first, then broader relevant checks.
11. Clear resolved debugging entries from `agent/session-state.md`.
12. Update design files only if the bug reveals durable behavior, boundary, or language knowledge.

## Session Error History

Use `agent/session-state.md` for current-session debugging history only.

Keep it bounded:

- Keep at most 5 failure entries.
- Keep each entry to about 10 lines or fewer.
- Prefer summaries over raw output.
- Record the failing command, short error summary, suspected bounded context, and next diagnostic step.
- Replace stale entries instead of appending indefinitely.
- Clear entries after the bug is fixed, the failure is no longer relevant, or the session ends.

Never store secrets, tokens, credentials, raw production data, or full logs in `agent/session-state.md`.

## Rules

- Treat tool output as the source of truth.
- Do not rewrite broad areas while debugging a narrow failure.
- Do not weaken existing tests unless a ratified design change explains why expected behavior changed.
- Do not store debugging history in canonical agent files.
- Do not use sub-agents unless the user explicitly asks for them.

## Final Response

- Root cause
- Fix made
- Checks run
- Checks skipped or unavailable
- Whether tests changed
- Whether session error history was updated or cleared
- Design files or ADRs updated
