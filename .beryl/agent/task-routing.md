# Task Routing

Purpose: choose the smallest task workflow to load. Do not load every workflow by default.

## Routing Rule

1. Classify the user's current request.
2. If `.beryl/agent/hierarchy.md` exists, resume the active initial-build workflow before classifying a new request, unless the user explicitly asks to pause or abandon that build.
3. Load exactly one matching workflow from `.beryl/agent/skills/<skill-name>/SKILL.md`.
4. Load canonical project files only when that workflow asks for them.
5. If the task changes, re-route before continuing.
6. For non-trivial work with multiple viable implementation paths, present the paths and wait for user approval unless the user explicitly allowed the agent to choose.

## Intent Map

| User Intent | Signals | Load |
| --- | --- | --- |
| Planning | plan, design, approach, architecture proposal, break this down | `.beryl/agent/skills/planning/SKILL.md` |
| Initial build | explicit request for a large application, greenfield application, or first coordinated build | `.beryl/agent/skills/initial-build/SKILL.md` |
| Feature addition | add, implement, build, create feature, new workflow, support behavior | `.beryl/agent/skills/adding-features/SKILL.md` |
| Debugging | debug, bug, error, failing, broken, regression, exception, test failure | `.beryl/agent/skills/debugging/SKILL.md` |
| Codebase explanation | explain, walk me through, understand, map the codebase, where is this handled | `.beryl/agent/skills/explaining-codebase/SKILL.md` |
| Post-run maintainability review | long product run, safe extraction slice, dead selectors, repeated CSS, rendering functions to split, generated artifacts, missing regression tests | `.beryl/agent/skills/tracking-entropy/SKILL.md` |

## Feature Implementation Gate

Feature implementation requires an approved plan.

- If the user asks for a feature and there is no approved plan in the current conversation or `.beryl/agent/design-tree.md`, load `adding-features` and produce the plan first.
- For non-trivial implementation plans, include implementation paths, acceptance criteria, commit boundaries, and risks before coding.
- Present the plan to the user and stop.
- Do not edit implementation code until the user ratifies the plan.
- After ratification, implement one internal feature slice at a time.
- Track feature-slice state internally in `.beryl/agent/session-state.md` only when needed for interruption or resume.
- Clear `.beryl/agent/session-state.md` when the feature is complete.
- Store only durable decisions in canonical files such as `.beryl/agent/design-tree.md`, `.beryl/agent/architecture.md`, `.beryl/agent/ubiquitous-language.md`, or `.beryl/agent/adr/*`.

## Initial Build Routing Gate

- Use `initial-build` only when the user explicitly requests a large application, a greenfield application, or the first coordinated build of a repository. Do not infer this route from ordinary feature size alone.
- Load the initial-build skill before asking build questions or editing files. Ask at most one clarification question per turn and wait for the answer before asking the next.
- Perform repository discovery before proposing the hierarchy. The discovery record may guide the plan, but it is not a substitute for user clarification.
- Present the scope, hierarchy, dependencies, deliverables, checks, context targets, and implementation order for user ratification. Do not create `.beryl/agent/hierarchy.md` or edit build code before explicit approval.
- After ratification, create the Git-tracked hierarchy with the schema defined by the initial-build skill. Update it and the relevant canonical Markdown as implementation progresses.
- Delete the hierarchy only after every node and required check passes and durable context promotion is complete. If a hierarchy already exists, resume it rather than creating a parallel plan.

## Sub-Agent Policy

Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

If the user explicity requests the use of sub-agents, spin up the following sub-agents:

- Design Reviewer (required sub-agent role: independent reviewer)
  Prompt:
  Review the feature brief and grill-me output before coding.
  Use only the Step 10-style checklist: language, bounded context, public interfaces, adapter isolation, tests, and coupling.
  Return only blockers, risk level (low/medium/high), and one exact fix per blocker.
  If no blockers, reply exactly: approved for implementation

- Architecture Reviewer (required sub-agent role: improving-architecture)
  Prompt:
  Review this slice for boundary drift.
  Return one minimal boundary improvement, the public API change, and the smallest protecting test.
  Do not propose broad cleanup.

- Slice Reviewer (required sub-agent role: code reviewer)
  Prompt:
  Review only the current slice diff plus narrow-check output.
  Report only blocking issues with exact fixes.
  Ignore style-only or optional cleanup.
  If no blockers, reply exactly: approved for next slice

- Final Reviewer (required sub-agent role: independent merge reviewer)
  Prompt:
  Review full diff and changed .beryl/agent/ docs before merge.
  Prioritize boundary drift, test weakening, adapter leakage, and stale instruction files.
  Report only merge blockers and exact fixes.
  If no blockers, reply exactly: approved for merge

## Supporting Skill Escalation

- Use `grill-me` for structured critique before risky, ambiguous, cross-context, or security-sensitive work.
- Use `interview-me` only when `grill-me` leaves an unresolved decision that depends on user judgment and cannot be answered from repository exploration.
- Use `frontend-design` for distinctive, intentional visual design when building new UI or reshaping an existing one.
- Use `tracking-entropy` after long product runs when the user asks for changed-file cleanup or one safe extraction slice.
- Do not use `interview-me` for routine task routing or discoverable codebase facts.
