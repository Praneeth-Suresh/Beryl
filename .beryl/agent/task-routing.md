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
| Planning and feature work | plan, design, approach, break this down, add, implement, build, change behavior | `.beryl/agent/skills/planning/SKILL.md` |
| Initial build | explicit request for a large application, greenfield application, or first coordinated build | `.beryl/agent/skills/initial-build/SKILL.md` |
| Module composition | add a dependency, reuse a library, choose a package, compose from modules | `.beryl/agent/skills/composing-modules/SKILL.md` |
| Debugging | debug, bug, error, failing, broken, regression, exception, test failure | `.beryl/agent/skills/systematic-debugging/SKILL.md` |
| Codebase understanding | explain, teach, walk me through, understand, map the codebase, explain a change/PR/commit/branch, show execution flow, or quiz me | `.beryl/agent/skills/understand-codebase/SKILL.md` |
| Codebase maintenance | whole repository: periodically refactor, reduce technical debt, maintain the codebase | `.beryl/agent/skills/maintaining-codebase/SKILL.md` |
| Context refresh | refresh, review, audit, or clean up the agent context or .beryl/agent docs; periodic context check; after a large restructure or migration | `.beryl/agent/skills/refreshing-context/SKILL.md` |
| Code simplification | a specific module or area: simplify, refactor, clean up, reduce complexity, improve code quality, design, or architecture | `.beryl/agent/skills/simplifying-code/SKILL.md` |

## Feature Implementation Gate

Feature implementation requires a plan the user has approved in the current
conversation.

- If there is no approved plan, load `planning`, present the plan, and stop.
- Do not edit implementation code until the user approves the plan.
- After approval, implement one commit boundary at a time as described in
  `planning`.
- Record only durable decisions, boundaries, and terms, in
  `.beryl/agent/architecture.md` or `.beryl/agent/ubiquitous-language.md`.

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
  Review the feature plan and any grill-me answers before coding.
  Use only the Step 10-style checklist: language, bounded context, public interfaces, adapter isolation, tests, and coupling.
  Return only blockers, risk level (low/medium/high), and one exact fix per blocker.
  If no blockers, reply exactly: approved for implementation

- Architecture Reviewer (required sub-agent role: architecture reviewer)
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
  Review the full diff and changed .beryl/agent/ docs before merge.
  Prioritize boundary drift, test weakening, adapter leakage, and stale instruction files.
  Report only merge blockers and exact fixes.
  If no blockers, reply exactly: approved for merge

## Supporting Skills

- `test-driven-development`: write the failing test first when adding or changing behavior.
- `verification-before-completion`: run the checks and read their output before claiming work is done.
- `grill-me`: structured interview before risky, ambiguous, cross-context, or security-sensitive work. It runs `grilling`.
- `communicating-with-users`: plans, questions, progress updates, and final reports.
- `creating-illustrations`: diagrams when a structure or flow is clearer drawn than described.
- `frontend-design`: distinctive, intentional visual design when building new UI or reshaping an existing one.
