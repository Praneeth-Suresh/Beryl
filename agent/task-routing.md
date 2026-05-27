# Task Routing

Purpose: choose the smallest task workflow to load. Do not load every workflow by default.

## Routing Rule

1. Classify the user's current request.
2. Load exactly one matching workflow from `agent/skills/<skill-name>/SKILL.md`.
3. Load canonical project files only when that workflow asks for them.
4. If the task changes, re-route before continuing.

## Intent Map

| User Intent | Signals | Load |
| --- | --- | --- |
| Planning | plan, design, approach, architecture proposal, break this down | `agent/skills/planning/SKILL.md` |
| Feature addition | add, implement, build, create feature, new workflow, support behavior | `agent/skills/adding-features/SKILL.md` |
| Debugging | debug, bug, error, failing, broken, regression, exception, test failure | `agent/skills/debugging/SKILL.md` |
| Codebase explanation | explain, walk me through, understand, map the codebase, where is this handled | `agent/skills/explaining-codebase/SKILL.md` |

## Feature Implementation Gate

Feature implementation requires an approved plan.

- If the user asks for a feature and there is no approved plan in the current conversation or `agent/design-tree.md`, load `adding-features` and produce the plan first.
- Present the plan to the user and stop.
- Do not edit implementation code until the user ratifies the plan.
- After ratification, implement one internal feature slice at a time.
- Track feature-slice state internally in `agent/session-state.md` only when needed for interruption or resume.
- Clear `agent/session-state.md` when the feature is complete.
- Store only durable decisions in canonical files such as `agent/design-tree.md`, `agent/architecture.md`, `agent/ubiquitous-language.md`, or `agent/adr/*`.

## Sub-Agent Policy

Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

If a workflow mentions reviewer or parallel-agent steps and the user did not explicitly request sub-agents, perform the review locally in the main agent.

## Supporting Skill Escalation

- Use `grill-me` for structured critique before risky, ambiguous, cross-context, or security-sensitive work.
- Use `interview-me` only when `grill-me` leaves an unresolved decision that depends on user judgment and cannot be answered from repository exploration.
- Do not use `interview-me` for routine task routing or discoverable codebase facts.
