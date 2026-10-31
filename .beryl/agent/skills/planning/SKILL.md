# Planning

## Purpose

Turn a requested change into a small, reviewable plan, get the user's approval,
and then implement it within the approved scope.

## Use When

- The user asks for a plan, design, approach, or breakdown.
- The user asks to add or change behavior and there is no approved plan yet.
- The user has approved a plan and implementation is next.

## Initial Build Handoff

When the request explicitly describes a large or greenfield application, route to
`.beryl/agent/skills/initial-build/SKILL.md` instead of using this general planning
workflow. A request to plan an ordinary feature remains in this workflow. If an
active `.beryl/agent/hierarchy.md` exists, resume the initial-build workflow and
implement only a dependency-ready hierarchy node.

## Plan

1. Restate the requested outcome.
2. Read only the canonical files needed for the relevant bounded context,
   usually `.beryl/agent/architecture.md`, `.beryl/agent/ubiquitous-language.md`,
   and `.beryl/agent/testing-policy.md`.
3. Identify the public interface, likely files, and checks that may change.
4. If more than one implementation path is plausible, present the options and
   wait for the user to choose, unless the user explicitly allowed you to choose.
5. Define success checks: the expected file or artifact change, a narrow
   command, a broader command, generated output or browser evidence when
   applicable, and one user-visible behavior.
6. Propose commit boundaries. Each one needs one purpose, the expected files,
   and the check command that validates it.
7. For risky or ambiguous work, run `grill-me` and fold the answers into the
   plan.
8. Present the plan, then stop. Do not edit implementation code until the user
   approves it.

For non-trivial work, use these headings:

```text
## Implementation Paths
## Acceptance Criteria
## Commit Boundaries
## Risks
```

## Implement

After the user approves the plan:

1. Implement one commit boundary at a time, behind the intended public
   interface. Use `test-driven-development` for new behavior.
2. Run the formatter if configured, then the narrow check, then the broader
   check.
3. If a check fails, use `systematic-debugging` and repair from the tool output.
4. If the work changes scope, stop and return to the plan.
5. Before saying the work is done, use `verification-before-completion`.
6. When a durable decision, boundary, or term changed, update
   `.beryl/agent/architecture.md` or `.beryl/agent/ubiquitous-language.md`.

## Rules

- Do not weaken tests to make implementation pass. Explain any intentional
  test change.
- Keep progress tracking out of canonical files.
- Do not use sub-agents unless the user explicitly asks for them.

## Final Response

Use `communicating-with-users`. Include what changed, a map from changed files
to commit boundaries (flag any file outside them), the checks that ran, the
checks that were skipped, and whether tests changed and why.
