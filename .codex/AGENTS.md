# Agent Operating Instructions

This tool-specific instruction file is a generated shim. Do not edit this copy manually. Update `.beryl/agent/tool-instruction-template.md` and rerun `.beryl/agent/scripts/sync-agent-env.sh`.

You are working in this repository as an implementation agent. Treat repository files as the source of truth. Do not rely on hidden chat history or assumptions when repo-owned instructions answer the question.

## Instruction Precedence

1. Explicit user instructions for the current task.
2. Canonical files under `.beryl/agent/`.
3. This generated shim.
4. Existing code, tests, and local conventions.

If this shim conflicts with canonical files under `.beryl/agent/`, treat this shim as stale, follow `.beryl/agent/`, and note the conflict.

## Required Context Before Editing

Before changing code or tests, read `.beryl/agent/task-routing.md`, classify the current task, and load only the matching workflow from `.beryl/agent/skills/<skill-name>/SKILL.md`.

Then read the smallest relevant set of canonical files requested by that workflow:

- `.beryl/agent/project-brief.md`
- `.beryl/agent/design-tree.md`
- `.beryl/agent/architecture.md`
- `.beryl/agent/ubiquitous-language.md`
- `.beryl/agent/testing-policy.md`
- `.beryl/agent/agent-rules.md`

Load additional files only when relevant.

## Always-On Operating Contract

These operating defaults apply in every agent session even when the user does not restate them. Users only need to speak up when they want to opt out of or override a default for the current prompt, such as explicitly allowing sub-agents.

- Route work through `.beryl/agent/task-routing.md` and the matching workflow skill before editing.
- Treat ratified feature implementation as `adding-features` work by default.
- Use `.beryl/agent/session-state.md` only as internal temporary state when needed, and clear it when the feature, repair, or debugging thread is complete.
- After edits in this Beryl source checkout, run the formatter command if one is configured, then narrow checks, then the broader deterministic gate `./.beryl/scripts/check.sh --development`. Installed projects run `./.beryl/scripts/check.sh`.
- Treat installed readiness as lock-aware: report an explicitly preserved root
  contract or hook as external ownership, never as silent Beryl enforcement.
- Use `install.sh --bootstrap-agent` only as a standalone action after a locked
  lifecycle operation. Its external-agent mutations are outside Beryl's file
  transaction.
- Never weaken tests to make implementation pass.
- If tests change intentionally, run `./.beryl/scripts/update-test-manifest.sh` and explain why the test and manifest changes were required.
- Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.
- For an explicit large or greenfield application request, load the `initial-build` workflow. Discover the repository, ask clarification questions one at a time, and obtain plan ratification before creating `.beryl/agent/hierarchy.md` or editing build code.
- Treat `.beryl/agent/hierarchy.md` as Git-tracked active-build state. Resume it when present, update it after each dependency-ordered slice, and delete it only after every node and check passes and durable context has been promoted.

## Skill Use

Skills live in `.beryl/agent/skills/<skill-name>/SKILL.md`.

Task workflows:

- `planning`: plans, designs, approaches, and feature planning gates.
- `initial-build`: clarifies, plans, ratifies, and implements large or greenfield applications through a tracked transient hierarchy.
- `adding-features`: feature implementation after a user-ratified plan.
- `debugging`: bugs, failures, regressions, exceptions, and failing checks.
- `explaining-codebase`: codebase walkthroughs and explanations without edits.

Supporting skills:

- `grill-me`: non-trivial feature, architecture change, cross-context change, ambiguous bug fix.
- `interview-me`: one-question-at-a-time user interview when `grill-me` leaves unresolved user-judgment decisions.
- `testing-vertical-slices`: feature/bug behavior implementation.
- `improving-architecture`: shallow modules, unclear boundaries, recurring coupling.
- `tracking-entropy`: maintainability review, post-run cleanup, hotspots, refactoring priority.
- `frontend-design`: distinctive, intentional visual design for new UI or UI reshaping.

When using a skill, follow its required inputs/outputs exactly.

Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

## Default Work Loop

1. Restate requested behavior and bounded context.
2. Identify intended public interface and likely files to change.
3. Add or identify the smallest deterministic test/check for behavior.
4. Before any meaningful redirect or implementation, state success checks: expected artifact change, narrow command, broader command, generated output or browser evidence when applicable, and one user-visible behavior.
5. For non-trivial work with multiple viable implementation paths, present the options and wait for user approval unless the user explicitly allowed you to choose.
6. Before coding, state commit boundaries: one purpose, expected files, and validating check command per boundary.
7. Implement one internal feature slice.
8. Run the formatter command if configured, then narrow checks, then broader checks.
9. Repair from actual tool output.
10. Update glossary/design-tree/architecture/ADR files if design knowledge changed.

For feature implementation, an approved plan is mandatory. If no approved plan exists, produce the plan first, present it to the user, and stop. Do not implement until the user ratifies the plan.

Feature slices are internal bookkeeping. Do not ask the user to manage slice IDs or ledgers. Use `.beryl/agent/session-state.md` for temporary session-specific implementation state when needed, and clear it when the feature is complete. Store only durable decisions in canonical files.

For post-run cleanup prompts, do not implement new features. Read changed files and return one safe extraction slice only, considering dead selectors, repeated CSS patterns, rendering functions that should be split, generated artifacts that should not be hand-edited, and tests missing for known regressions.

## Engineering Rules

- Prefer existing project patterns over new abstractions.
- Keep public interfaces small and explicit.
- Do not import internals from another bounded context.
- Keep external systems behind adapters.
- Use terms from `.beryl/agent/ubiquitous-language.md`.
- Do not weaken tests to make implementation pass.
- Do not edit unrelated files.
- Do not store secrets in repo files, prompts, or logs.
- Do not let temporary implementation notes accumulate in canonical agent files.
- Keep session debugging history bounded in `.beryl/agent/session-state.md`; summarize failures, cap entries, and clear resolved errors.

Before deleting or consolidating root planning or documentation files, list every file, what is preserved, what is lost, and where replacement content lives, then wait for explicit approval.

The completed initial-build hierarchy is a narrow exception: after every node
and required check passes and durable context has been promoted, delete only
`.beryl/agent/hierarchy.md` as specified by the `initial-build` workflow. Do not
extend this exception to other planning or documentation files.

## Browser Verification Rule

- For web app, HTML, or CSS tasks, prefer **Microsoft Playwright MCP** as the browser tool.
- Use browser state/tool output (for example accessibility snapshots and DOM state) as the source of truth for UI verification.
- Do not mark browser-related work complete until the behavior is confirmed through Playwright MCP checks.

For static-site changes, source inspection is not enough. Verify affected generated output such as `dist` HTML, sitemap, robots, search index, feeds, copied assets, and browser behavior when relevant.

## Verification

Run checks required by `.beryl/agent/testing-policy.md` and local project tooling.

Final response must include:

- What changed.
- Map each changed file to the intended commit boundary.
- Flag any changed file that does not belong to a stated commit boundary.
- Checks run.
- Checks skipped or unavailable.
- Design files/ADR updates.
- Whether temporary session state was cleared or why it remains.
