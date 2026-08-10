# Initial Build

## Purpose

Guide the first coordinated implementation of a large or greenfield application
in a repository where Beryl is installed. Clarification questions are part of
the workflow and precede approval of a dependency-ordered build that can resume
across agent sessions. It is an instruction contract, not a model-, vendor-,
CLI-, or tool-specific implementation.

## Use When

Use this workflow only when the user explicitly asks to build a large
application, start a greenfield application, or coordinate the repository's
first substantial build. Ordinary feature work, repairs, debugging, and
explanations use their normal workflows.

If `.beryl/agent/hierarchy.md` already exists, treat it as an active initial
build and resume this workflow. Do not create a second hierarchy or restart the
interview without first reading the existing hierarchy and asking the user
whether they want to pause or abandon that build.

## Required Context

Read these files before making a plan or changing code:

- `.beryl/agent/project-brief.md`
- `.beryl/agent/design-tree.md`
- `.beryl/agent/architecture.md`
- `.beryl/agent/ubiquitous-language.md`
- `.beryl/agent/testing-policy.md`
- `.beryl/agent/agent-rules.md`
- `.beryl/agent/task-routing.md`

Then inspect the repository's source tree, package/build configuration, existing
tests, entry points, deployment configuration, and relevant documentation. Use
the repository as the source of truth. Do not treat hidden chat history as
project context.

## New-Build Process

Follow these phases in order. Do not skip a gate because the request sounds
clear.

### 1. Discover the repository

Before proposing architecture or implementation work, identify what already
exists: stack and entry points, executable commands, test and check commands,
data and integration boundaries, deployment targets, existing conventions,
constraints, and relevant gaps. Record only the facts needed to ask useful
questions and form a plan; do not create `hierarchy.md` during discovery.

### 2. Clarify one question at a time

Ask exactly one focused question per turn and wait for the user's answer before
asking another. Prefer a recommended default when a choice is not already
settled by the repository. Cover the decisions that materially affect the
build, including:

- primary users, outcomes, and highest-value workflows;
- required platforms, integrations, data ownership, and security or privacy
  constraints;
- scope boundaries, non-goals, rollout assumptions, and delivery constraints;
- acceptance criteria, operational expectations, and required checks.

Do not ask questions whose answers can be discovered from the repository. Keep
answers in the conversation until they become durable project knowledge.

### 3. Develop the hierarchical plan

After clarification, propose a complete plan before editing build code. Decompose
the request into a hierarchy of deliverables, not a flat list of prompts. Cover
product boundaries, domain/data boundaries, architecture and adapters,
vertical slices, migrations or rollout, testing, observability, documentation,
and operational checks as applicable.

For every node, state its parent, dependencies, deliverable, acceptance checks,
status, and canonical context targets. Order nodes so a node is implemented only
when all of its dependencies are complete. Make dependencies explicit even when
two nodes are in the same feature area. Include non-goals and assumptions in the
proposal so the user can review scope rather than only tasks.

### 4. Require ratification

Present the clarified scope and the full hierarchy, including implementation
order, dependencies, deliverables, checks, context targets, risks, and open
assumptions. Ask the user to ratify the plan. Silence, a partial answer, or a
request to keep planning is not ratification.

Before ratification:

- do not create `.beryl/agent/hierarchy.md`;
- do not edit application code or build configuration;
- do not claim that implementation has started.

If the user changes scope, update the proposal and seek ratification again.

### 5. Create the tracked hierarchy

Only after explicit ratification, create `.beryl/agent/hierarchy.md` in the
repository. It is intentionally Git-tracked and must not be added to a
gitignore. The file is authoritative for active initial-build order and
progress, but it is a transient lifecycle artifact rather than permanent
project documentation.

Verify that `git check-ignore .beryl/agent/hierarchy.md` does not report the
file, then run `git add .beryl/agent/hierarchy.md` as part of preparing the
first build commit the user authorizes. If an ignore rule or Git error prevents
staging it, stop and resolve that condition instead of continuing with an
untracked hierarchy. Do not claim that it is Git-tracked until `git ls-files
.beryl/agent/hierarchy.md` confirms it. Keep later hierarchy updates in the
same authorized commits as their corresponding implementation slices so a
checkout contains the active build state. Do not create an otherwise
unauthorized commit only to track the hierarchy.

Use this minimum schema:

```markdown
# Initial Build Hierarchy

## Build Contract
- Scope:
- Non-goals:
- Ratified on:
- Last updated:
- Completion rule: every node and required check passes, durable context is promoted

## Nodes

### <stable-node-id> — <short name>
- Parent: <stable-node-id or root>
- Dependencies: <stable-node-id list or none>
- Deliverable: <observable result>
- Acceptance checks:
  - <command, test, inspection, or user-visible check>
- Status: pending | ready | in-progress | blocked | complete
- Canonical context targets:
  - <.beryl/agent/<file>.md or none>
- Evidence: <short command/result or link to review evidence>
```

Every node must have all seven fields: stable id, parent, dependencies,
deliverable, acceptance checks, status, and canonical context targets. Keep the
hierarchy readable in ordinary Markdown. Do not store secrets in it.

### 6. Implement in dependency order

Select only nodes whose dependencies are complete. Implement one coherent
vertical slice at a time using the normal feature, testing, architecture, and
security workflows. Before each slice, confirm the node's acceptance checks and
the relevant host-project commands. After each slice:

1. Run the node's narrow checks, then the broader deterministic project gate.
2. Update the node status and evidence in `hierarchy.md`.
3. Update canonical Markdown when a durable scope decision, boundary,
   vocabulary term, architecture decision, or verification rule changes.
4. Keep progress notes, temporary rationale, and unresolved scratch details in
   `hierarchy.md` or the ignored `session-state.md`, not in canonical docs.

If a node is blocked, mark it blocked with the concrete reason and do not
implement dependent nodes. Re-plan affected nodes and seek user ratification if
scope, dependencies, or acceptance criteria change materially.

### 7. Promote durable context and complete

Before declaring the initial build complete, verify that every node is complete,
every required node and project check passes, and all durable knowledge has been
promoted to the smallest relevant canonical file. Durable knowledge includes
settled scope and non-goals, bounded-context ownership, public interfaces,
adapters, stable vocabulary, architecture decisions, and verification rules.

Do not copy the hierarchy wholesale into canonical files. Progress, sequencing,
temporary rationale, and completed-node evidence are lifecycle state.

Only after those conditions pass may you delete `.beryl/agent/hierarchy.md`.
Deletion is the narrow declared exception to the normal documentation deletion
safeguard: preserve the durable promotions first, verify the completion gate,
then remove only this file. Include the deletion in the same authorized final
build commit as the last durable promotions, and verify that the completed tree
no longer tracks the file. Report the deletion and the checks that authorized
it. If any node or check remains incomplete, keep the file and resume later.

## Resumption

At the start of every session, check for `.beryl/agent/hierarchy.md` before
starting a new build. If present, read its build contract, node statuses,
dependencies, blocked reasons, evidence, and context targets. Continue from the
first dependency-ready node. Reconcile the hierarchy with the current working
tree before editing; if the tree or user request conflicts with it, pause that
node and ask one focused question.

## Completion Checklist

- [ ] The request was explicitly classified as a large or greenfield initial build.
- [ ] Repository discovery happened before the hierarchy was proposed.
- [ ] Clarification questions were asked one at a time.
- [ ] Scope, non-goals, hierarchy, dependencies, deliverables, checks, and
      context targets were explicitly ratified.
- [ ] `hierarchy.md` was created only after ratification and was Git-tracked.
- [ ] The hierarchy entered the first authorized build commit and its updates
      were committed with their implementation slices.
- [ ] Nodes were implemented only after their dependencies completed.
- [ ] Hierarchy statuses and evidence were updated after each slice.
- [ ] Durable context was promoted to canonical Markdown as it changed.
- [ ] Every node and required check passed before deletion.
- [ ] `hierarchy.md` was deleted only after the previous conditions passed.
- [ ] The deletion was committed with the final durable context promotions.

## Output Contract

When stopping before ratification, report the discovery findings, unanswered
question (one at a time), proposed scope, and what remains before approval.

When implementing, report the active node, dependency status, changed files,
context promotions, checks, evidence, and next dependency-ready node. At
completion, report the durable files updated, all checks run, and the authorized
deletion of `hierarchy.md`.
