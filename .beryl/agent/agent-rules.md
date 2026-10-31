# Agent Rules

Beryl-specific rules for agents. General coding practice comes from the skills
in `.beryl/agent/skills/`.

## Always-On Operating Defaults

These defaults apply in every session. Users only need to mention one to override it for the current prompt, such as explicitly allowing sub-agents.

1. Route work through `.beryl/agent/task-routing.md` and the matching skill before editing.
2. Feature work needs a plan the user has approved. Without one, load `planning`, present the plan, and stop.
3. After edits, run the formatter command if configured, then narrow checks, then `./.beryl/scripts/check.sh --development` in this source checkout (installed projects use `./.beryl/scripts/check.sh`).
4. Never weaken tests to make implementation pass.
5. If tests change intentionally, explain why the test changes were required.
6. Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.
7. For an explicit large or greenfield application request, load the `initial-build` workflow. Discover the repository, ask clarification questions one at a time, and obtain plan ratification before creating `.beryl/agent/hierarchy.md` or editing build code.
8. Treat `.beryl/agent/hierarchy.md` as Git-tracked active-build state. Resume it when present, update it after each dependency-ordered slice, and delete it only after every node and check passes and durable context has been promoted.

## Repository Context

1. Record durable decisions, boundaries, open questions, and pressure points in `.beryl/agent/architecture.md`, and terms in `.beryl/agent/ubiquitous-language.md`.
2. Keep progress notes and temporary state out of canonical files.
3. Do not create sub-module agent structures unless the project has 3+ independently complex bounded contexts declared in root `.beryl/agent/architecture.md` (in which case, read through `.beryl/agent/guides/sub-module-agents.md` for more details). For smaller projects, the root `.beryl/agent/` is sufficient and sub-modules waste context.
4. When the context files may no longer match the code, use `refreshing-context` with the user rather than guessing.
5. Do not edit skills listed in `.beryl/agent/skills/VENDORED.md`; they are unmodified upstream copies.

## Deletion And Consolidation Safeguard

Before deleting or consolidating root planning or documentation files:

1. List every file to delete or consolidate.
2. State what information is preserved.
3. State what information is lost.
4. State where replacement content will live.
5. Wait for explicit user approval before editing those files.

The completed initial-build hierarchy is a narrow exception: after every node
and required check passes and durable context has been promoted, delete only
`.beryl/agent/hierarchy.md` as specified by the `initial-build` workflow. Do not
extend this exception to other planning or documentation files.

## Final Response Contract

Follow `communicating-with-users`. Final response must include:

- What changed.
- Map each changed file to the intended commit boundary.
- Flag any changed file that does not belong to a stated commit boundary.
- Which checks ran.
- Which checks were skipped or unavailable.
- Whether tests changed, and why.
- Which skill(s) were used.
