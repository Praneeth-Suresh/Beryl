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
4. For non-trivial work, identify viable implementation paths. If more than one path is plausible, present the options and wait for user approval unless the user explicitly allowed the agent to choose.
5. Define success checks before implementation. Include the expected file, route, or artifact change; narrow command; broader command; generated output or browser evidence when applicable; and one user-visible behavior.
6. Propose commit boundaries for implementation. Each boundary needs one purpose, expected files, and the check command that validates it.
7. Split implementation into internal feature slices when more than one safe implementation step is involved.
8. For risky or ambiguous work, run `grill-me` locally and fold the critique into the plan.
9. Run `interview-me` only if `grill-me` leaves an unresolved user-judgment question that cannot be answered from the repo.
10. Present the user-facing plan and wait for user ratification before implementation.

## Internal State

- Do not ask the user to manage feature slices.
- Do not put temporary feature-slice state in `.beryl/agent/design-tree.md`.
- If interruption or resume support is needed, write the smallest internal checklist to `.beryl/agent/session-state.md`.
- `.beryl/agent/session-state.md` is session-specific and gitignored.
- Remove or clear `.beryl/agent/session-state.md` when the feature is complete.
- Move only durable decisions into `.beryl/agent/design-tree.md`, `.beryl/agent/architecture.md`, `.beryl/agent/ubiquitous-language.md`, or `.beryl/agent/adr/*`.

## Output

- Requested outcome
- Bounded context
- Implementation paths for non-trivial work
- Proposed approach, or explicit request for user path approval
- Implementation approach, summarized without slice IDs
- Success checks before implementation
- Commit boundaries before implementation
- Risks: scope, architecture, and UX when applicable
- Tests/checks to run
- Design files or ADRs likely to change
- Open questions or assumptions

For non-trivial implementation tasks, include these headings before coding:

```text
## Implementation Paths
...

## Acceptance Criteria
- Source-level check:
- Generated-output check:
- Browser/user-visible check:
- Test/check command:

## Commit Boundaries
- Commit 1:

## Risks
- Scope risk:
- Architecture risk:
- UX risk:
```

## Stop Condition

When this workflow is used as the planning gate for feature implementation, stop after presenting the plan. Do not edit code until the user ratifies the plan.
