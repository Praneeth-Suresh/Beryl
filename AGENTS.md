# Agent Operating Instructions

This tool-specific instruction file is a generated shim. Do not edit this copy manually. Update `agent/tool-instruction-template.md` and rerun `agent/scripts/sync-agent-env.sh`.

You are working in this repository as an implementation agent. Treat repository files as the source of truth. Do not rely on hidden chat history or assumptions when repo-owned instructions answer the question.

## Instruction Precedence

1. Explicit user instructions for the current task.
2. Canonical files under `agent/`.
3. This generated shim.
4. Existing code, tests, and local conventions.

If this shim conflicts with canonical files under `agent/`, treat this shim as stale, follow `agent/`, and note the conflict.

## Required Context Before Editing

Before changing code or tests, read `agent/task-routing.md`, classify the current task, and load only the matching workflow from `agent/skills/<skill-name>/SKILL.md`.

Then read the smallest relevant set of canonical files requested by that workflow:

- `agent/project-brief.md`
- `agent/design-tree.md`
- `agent/architecture.md`
- `agent/ubiquitous-language.md`
- `agent/testing-policy.md`
- `agent/agent-rules.md`

Load additional files only when relevant.

## Skill Use

Skills live in `agent/skills/<skill-name>/SKILL.md`.

Task workflows:

- `planning`: plans, designs, approaches, and feature planning gates.
- `adding-features`: feature implementation after a user-ratified plan.
- `debugging`: bugs, failures, regressions, exceptions, and failing checks.
- `explaining-codebase`: codebase walkthroughs and explanations without edits.

Supporting skills:

- `grill-me`: non-trivial feature, architecture change, cross-context change, ambiguous bug fix.
- `interview-me`: one-question-at-a-time user interview when `grill-me` leaves unresolved user-judgment decisions.
- `testing-vertical-slices`: feature/bug behavior implementation.
- `improving-architecture`: shallow modules, unclear boundaries, recurring coupling.
- `tracking-entropy`: maintainability review, hotspots, refactoring priority.
- `frontend-design`: distinctive, intentional visual design for new UI or UI reshaping.

When using a skill, follow its required inputs/outputs exactly.

Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

## Default Work Loop

1. Restate requested behavior and bounded context.
2. Identify intended public interface and likely files to change.
3. Add or identify the smallest deterministic test/check for behavior.
4. Implement one internal feature slice.
5. Run narrow checks, then broader checks.
6. Repair from actual tool output.
7. Update glossary/design-tree/architecture/ADR files if design knowledge changed.

For feature implementation, an approved plan is mandatory. If no approved plan exists, produce the plan first, present it to the user, and stop. Do not implement until the user ratifies the plan.

Feature slices are internal bookkeeping. Do not ask the user to manage slice IDs or ledgers. Use `agent/session-state.md` for temporary session-specific implementation state when needed, and clear it when the feature is complete. Store only durable decisions in canonical files.

## Engineering Rules

- Prefer existing project patterns over new abstractions.
- Keep public interfaces small and explicit.
- Do not import internals from another bounded context.
- Keep external systems behind adapters.
- Use terms from `agent/ubiquitous-language.md`.
- Do not weaken tests to make implementation pass.
- Do not edit unrelated files.
- Do not store secrets in repo files, prompts, or logs.
- Do not let temporary implementation notes accumulate in canonical agent files.
- Keep session debugging history bounded in `agent/session-state.md`; summarize failures, cap entries, and clear resolved errors.

## Browser Verification Rule

- For web app, HTML, or CSS tasks, prefer **Microsoft Playwright MCP** as the browser tool.
- Use browser state/tool output (for example accessibility snapshots and DOM state) as the source of truth for UI verification.
- Do not mark browser-related work complete until the behavior is confirmed through Playwright MCP checks.

## Verification

Run checks required by `agent/testing-policy.md` and local project tooling.

Final response must include:

- What changed.
- Checks run.
- Checks skipped or unavailable.
- Design files/ADR updates.
- Whether temporary session state was cleared or why it remains.
