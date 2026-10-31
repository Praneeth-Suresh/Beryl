# Agent Operating Instructions

This tool-specific instruction file is a generated shim. Do not edit this copy manually. Update `.beryl/agent/tool-instruction-template.md` and rerun `.beryl/agent/scripts/sync-agent-env.sh`.

Treat repository files as the source of truth. Do not rely on hidden chat history when repo-owned instructions answer the question.

## Instruction Precedence

1. Explicit user instructions for the current task.
2. Canonical files under `.beryl/agent/`.
3. This generated shim.
4. Existing code, tests, and local conventions.

If this shim conflicts with canonical files under `.beryl/agent/`, treat this shim as stale, follow `.beryl/agent/`, and note the conflict.

## Before Editing

Read `.beryl/agent/task-routing.md`, classify the current task, and load only the matching skill from `.beryl/agent/skills/<skill-name>/SKILL.md`. Then read only the canonical files that skill asks for:

- `.beryl/agent/project-brief.md`
- `.beryl/agent/architecture.md`
- `.beryl/agent/ubiquitous-language.md`
- `.beryl/agent/testing-policy.md`
- `.beryl/agent/agent-rules.md`

## Always-On Operating Contract

These defaults apply in every session. Users only need to mention one to override it, for example to allow sub-agents.

- Feature work needs a plan the user has approved. Without one, load `planning`, present the plan, and stop.
- For an explicit large or greenfield application request, load the `initial-build` workflow. Discover the repository, ask clarification questions one at a time, and obtain plan ratification before creating `.beryl/agent/hierarchy.md` or editing build code.
- Treat `.beryl/agent/hierarchy.md` as Git-tracked active-build state. Resume it when present, update it after each dependency-ordered slice, and delete it only after every node and check passes and durable context has been promoted.
- After edits in this Beryl source checkout, run the formatter command if one is configured, then narrow checks, then the broader deterministic gate `./.beryl/scripts/check.sh --development`. Installed projects run `./.beryl/scripts/check.sh`.
- Treat installed readiness as lock-aware: report an explicitly preserved root
  contract or hook as external ownership, never as silent Beryl enforcement.
- Use `install.sh --bootstrap-agent` only as a standalone action after a locked
  lifecycle operation. Its external-agent mutations are outside Beryl's file
  transaction.
- Never weaken tests to make implementation pass. If tests change intentionally, explain why.
- Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.
- Record durable decisions, boundaries, and terms in `.beryl/agent/architecture.md` or `.beryl/agent/ubiquitous-language.md`. Keep progress notes out of canonical files.

## Skills

Task workflows:

- `planning`: plans, designs, and approved feature implementation.
- `initial-build`: large or greenfield applications through a tracked transient hierarchy.
- `systematic-debugging`: bugs, failures, regressions, and failing checks.
- `understand-codebase`: read-only codebase teaching, including safe offline understanding artifacts.
- `composing-modules`: evidence-led, approval-gated dependency and module selection.
- `maintaining-codebase`: evidence-led, approval-gated whole-repository maintenance program.
- `simplifying-code`: evidence-led, behavior-preserving simplification of a module or area.
- `refreshing-context`: periodic or post-change check of the context files against the code, with a developer quiz.

Supporting skills:

- `test-driven-development`: write the failing test first.
- `verification-before-completion`: evidence before claiming work is done.
- `grill-me`: structured interview for risky or ambiguous plans.
- `communicating-with-users`: plans, questions, updates, and final reports.
- `creating-illustrations`: diagrams for structures and flows.
- `frontend-design`: distinctive visual design for new or reshaped UI.

Skills listed in `.beryl/agent/skills/VENDORED.md` are unmodified upstream copies. Do not edit them in place.

## Deletion Safeguard

Before deleting or consolidating root planning or documentation files, list every file, what is preserved, what is lost, and where replacement content lives, then wait for explicit approval.

The completed initial-build hierarchy is a narrow exception: after every node
and required check passes and durable context has been promoted, delete only
`.beryl/agent/hierarchy.md` as specified by the `initial-build` workflow. Do not
extend this exception to other planning or documentation files.

## Browser Verification

For web app, HTML, or CSS tasks, verify behavior in a real browser, preferably with **Microsoft Playwright MCP**, and treat browser state as the source of truth. For static sites, also verify affected generated output such as built HTML, sitemap, feeds, and copied assets.

## Final Response

Follow `communicating-with-users`. Include:

- What changed, mapped to the intended commit boundaries, with any file outside them flagged.
- Checks run, and checks skipped or unavailable.
- Whether tests changed, and why.
- Canonical files updated.
