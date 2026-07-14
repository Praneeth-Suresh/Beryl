# Repository Upkeep

This guide is the tracked operating system for maintaining ideas and materials in this repository. It decides where new context belongs, when scratch notes become durable, and how maintainers verify that upkeep did not change runtime behavior.

## Intake

Use one of these lanes for every new idea or material.

| Lane | Use For | Where It Starts | Promotion Target |
| --- | --- | --- | --- |
| Durable idea | A decision, workflow, vocabulary term, user-facing doc update, or review rule that future maintainers should rely on. | Issue, task brief, planning note, or review comment. | Root docs, `.beryl/agent/design-tree.md`, `.beryl/agent/architecture.md`, `.beryl/agent/ubiquitous-language.md`, or `.beryl/agent/adr/*`. |
| Temporary snapshot | Current local context, working notes, failed command excerpts, or implementation slice state. | `current.md`, `.beryl/agent/session-state.md`, or `.beryl/driver/state/<task-id>/session-state.md`. | Promote only the durable conclusion, then clear or leave the scratch file ignored. |
| Task backlog | Work that is valuable but not part of the active slice. | GitHub issue, driver task brief, or explicit follow-up note. | A tracked task file or issue comment owned by the driver or maintainer. |
| Archive or discard | Superseded ideas, duplicate notes, or material that no longer reflects the repository. | Any planning or scratch source. | Delete, leave in Git history, or summarize the reason in the relevant task state. |

Treat hidden chat history and local scratch files as leads, not authority. The repository files are the source of truth.

## Promotion Rules

Promote material when it changes what future users or agents should do.

- Use [README.md](./README.md) for the top-level documentation map and the most important entry points.
- Use [Quickstart.md](./Quickstart.md) for first-run onboarding and the shortest safe path.
- Use [Theory.md](./Theory.md) for product reasoning and design motivation.
- Use [Practise.md](./Practise.md) for applied examples.
- Use [Cheatsheet.md](./Cheatsheet.md) for command and workflow reference.
- Use [.beryl/agent/design-tree.md](./.beryl/agent/design-tree.md) for open or settled decisions that may guide future implementation.
- Use [.beryl/agent/architecture.md](./.beryl/agent/architecture.md) for bounded contexts, public entry points, and boundary rules.
- Use [.beryl/agent/ubiquitous-language.md](./.beryl/agent/ubiquitous-language.md) for stable terms agents should use consistently.
- Use `.beryl/agent/adr/*` when a durable decision changes module boundaries, persistence shape, adapter contracts, security model, naming conventions across contexts, or test strategy.

Do not promote raw session logs, copied issue bodies, or failed command output wholesale. Extract the decision, behavior, risk, or command result that future work needs.

When material starts in `current.md`, treat it as local scratch context. Keep only the durable conclusion in tracked files and avoid making `current.md` the review artifact.

## Upkeep Cadence

Before feature work:

- Read the README documentation map and the workflow selected by `.beryl/agent/task-routing.md`.
- Check whether the task changes a design decision, term, boundary, or ADR-worthy rule.
- Identify the smallest tracked file that should receive any durable update.

After feature work:

- Confirm scratch notes did not become the only record of a decision.
- Clear temporary agent session state when the thread is complete.
- Update this guide only when the intake or promotion system itself changes.

Weekly or monthly maintenance:

- Run `.beryl/agent/scripts/entropy-hotspots.sh` to find high-churn material.
- Use `.beryl/agent/skills/tracking-entropy/SKILL.md` for one safe extraction slice when upkeep work is needed.
- Review stale scratch references, broken documentation links, and duplicated command guidance.

## Verification

For docs-only upkeep changes, run:

```bash
./.beryl/scripts/check-md.sh
./.beryl/agent/scripts/agent-doctor.sh
./.beryl/scripts/check.sh
```

Use a source-level search when the change introduces a new durable concept:

```bash
rg -n "RepositoryUpkeep\\.md|Repository Upkeep|Material Intake" README.md RepositoryUpkeep.md .beryl/agent/design-tree.md .beryl/agent/ubiquitous-language.md
```

If tests change intentionally, follow [.beryl/agent/testing-policy.md](./.beryl/agent/testing-policy.md) and run `./.beryl/scripts/update-test-manifest.sh`. Do not weaken tests to make an upkeep change pass.

## Out Of Scope

This guide does not own GitHub comment finalization, pushing commits, remote issue closure, network access, or authentication. Linked issue comments and close attempts are driver-owned soft finalization steps after a verified local commit.

This guide also does not replace human product judgment. It keeps the material visible, reviewable, and easy to route.
