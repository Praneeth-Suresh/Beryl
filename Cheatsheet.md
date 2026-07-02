# Agent Project Setup Cheatsheet

Use this when starting a new software project from this boilerplate. The goal is simple: copy the control plane, fill the project facts, wire the checks, then make every agent change follow the same loop.

## 0. Run The Setup Script

For the lowest-friction setup, run:

```bash
./scripts/setup-project.sh /path/to/new-project
```

The script asks for the target directory, stack, test runner, and whether to enable the Git hook. If the listed choices are not enough, choose `Use AI agent fallback`; the script will ask for a setup prompt and run Codex, Claude, or a custom headless command from inside the target project.

After this succeeds, skip to "Fill The Minimum Project Facts".

## 0.1 Manual Boilerplate Copy

From this repository, copy these paths into the new project root:

```bash
cp -R agent /path/to/new-project/
cp -R scripts /path/to/new-project/
cp -R githooks /path/to/new-project/
cp -R .github /path/to/new-project/
cp CLAUDE.md /path/to/new-project/ 2>/dev/null || true
```

Then enter the new project:

```bash
cd /path/to/new-project
```

Make scripts executable if needed:

```bash
chmod +x scripts/*.sh agent/scripts/*.sh githooks/pre-commit
```

Ignore temporary agent session state:

```bash
grep -qxF 'agent/session-state.md' .gitignore 2>/dev/null || printf '\nagent/session-state.md\n' >> .gitignore
```

Generate tool-specific instruction shims:

```bash
./agent/scripts/sync-agent-env.sh
```

Create the first manifest:

```bash
./scripts/update-test-manifest.sh
```

If your repo ignores a generated tool directory such as `.codex/`, either track the needed shim explicitly or adjust `agent/scripts/agent-doctor.sh` so CI does not require ignored local files.

## 0.2 Configure Browser MCP (Web/HTML Work)

For deterministic browser feedback, standardize on **Microsoft Playwright MCP**.

1. Ensure Node.js 18+ is available.
2. Register Playwright MCP in Codex:

```bash
codex mcp add playwright npx "@playwright/mcp@latest"
codex mcp list
```

3. If you prefer config files, add this to `~/.codex/config.toml` (or project `.codex/config.toml`):

```toml
[mcp_servers.playwright]
command = "npx"
args = ["@playwright/mcp@latest"]
```

4. For web UI tasks, prompt the agent to verify behavior in Playwright MCP before marking work done.

## 1. Fill The Minimum Project Facts

Do this before asking an agent to build features.

Edit:

```text
agent/project-brief.md
agent/design-tree.md
agent/ubiquitous-language.md
agent/architecture.md
agent/testing-policy.md
agent/security-policy.md
```

Minimum required content:

1. `project-brief.md`: product goal, users, 3 to 5 core workflows, non-goals, external systems, definition of done.
2. `design-tree.md`: current design concept, open decisions, settled decisions, pressure points.
3. `ubiquitous-language.md`: domain terms agents must use in prompts, code, and tests.
4. `architecture.md`: bounded contexts, ownership, public entry points, forbidden imports.
5. `testing-policy.md`: exact commands for format, lint, typecheck, unit tests, integration tests, E2E smoke, and `check`.
6. `security-policy.md`: secrets rules, approval-required operations, external access limits.

Run:

```bash
./agent/scripts/agent-doctor.sh
./scripts/check.sh
```

Fix anything that fails before implementation starts.

## 2. Configure The Test Manifest

The test manifest tells you if test files changed since the last approved baseline.

Edit:

```text
agent/test-manifest.conf
```

Set:

```bash
MANIFEST_PATH="tests/.manifest.sha256"
INCLUDE_GLOBS=(
  "tests/**"
  "spec/**"
  "src/**/__tests__/**"
  "**/*.test.*"
  "**/*.spec.*"
  "**/*_test.go"
  "**/*_test.py"
)
EXCLUDE_GLOBS=(
  ".git/**"
  "node_modules/**"
  "vendor/**"
  ".venv/**"
  "dist/**"
  "build/**"
  "coverage/**"
)
```

Create the first manifest:

```bash
./scripts/update-test-manifest.sh
```

Check that tests are unchanged:

```bash
./scripts/check-tests-unchanged.sh
```

Normal rule:

- Run `./scripts/check-tests-unchanged.sh` when you want assurance that tests did not move.
- Run `./scripts/update-test-manifest.sh` only when a test change is intentional.
- Commit the test change and manifest change together.

## 3. Configure The Project Check

Configure the affected test gate:

```text
agent/affected-tests.conf
```

This keeps the developer workflow small: developers enable the Git hook once, and commits automatically run the relevant project tests for staged changes.

Set `RELATED_TEST_CMD` when your test runner can select tests from changed files. Set `FULL_TEST_CMD` for broad changes that should run the whole suite.

Examples:

```bash
# Jest
RELATED_TEST_CMD=(npx --no-install jest --findRelatedTests --passWithNoTests)
FULL_TEST_CMD=(npm test)

# pytest with testmon
RELATED_TEST_CMD=(pytest --testmon)
FULL_TEST_CMD=(pytest)
```

`scripts/check-project.sh` is already wired to call `scripts/check-affected.sh`; keep custom project checks behind that gate unless they are fast enough to run on every commit.

Required order:

1. Formatter check.
2. Linter.
3. Typecheck.
4. Affected unit/integration tests, with full-test fallback for broad changes.

Use non-mutating formatter check mode in `check-project.sh` when the tool supports it. Agents should still run the mutating formatter command immediately after writing code, but the shared gate should fail cleanly in hooks and CI instead of silently rewriting files.

Examples:

```bash
npm run format:check
npm run lint
npm run typecheck
./scripts/check-affected.sh --worktree
```

or:

```bash
ruff format --check .
ruff check .
pyright
./scripts/check-affected.sh --worktree
```

or:

```bash
test -z "$(gofmt -l .)"
go vet ./...
golangci-lint run
./scripts/check-affected.sh --worktree
```

Also update `agent/testing-policy.md` so agents know both commands:

| Stack                 | Formatter after edits | Formatter check in `check-project.sh` | Linter                                        |
| --------------------- | --------------------- | --------------------------------------- | --------------------------------------------- |
| TypeScript/JavaScript | `npm run format`    | `npm run format:check`                | `npm run lint`                              |
| Python                | `ruff format .`     | `ruff format --check .`               | `ruff check .`                              |
| Go                    | `gofmt -w .`        | `test -z "$(gofmt -l .)"`             | `go vet ./...` and/or `golangci-lint run` |

Then run the full gate:

```bash
./scripts/check.sh
```

Use `./scripts/check.sh` as the manual "am I still safe?" command. Manual checks use worktree changes. Commit hooks use staged changes.

## 4. Optional Git Hook

Enable the pre-commit hook if you want checks before every commit:

```bash
git config core.hooksPath githooks
```

The hook runs:

```bash
./scripts/check.sh
```

During commits, it sets `CHECK_AFFECTED_MODE=staged`, so the affected test gate selects tests from exactly what is being committed. Developers do not need to pass file lists or choose test commands manually.

Skip this if you only want to run checks manually.

## 5. Optional CI

The copied workflow is:

```text
.github/workflows/deterministic-checks.yml
```

It runs:

```bash
./scripts/check.sh
./agent/scripts/agent-doctor.sh
```

Before relying on CI, verify that every file required by `agent-doctor.sh` is tracked by Git or generated during the workflow.

## 6. First Agent Prompt For A New Project

Use this before implementation:

```text
Plan the initial project design.

Use agent/task-routing.md and the planning workflow.
Requested outcome: [what the project should do]
First bounded context: [context]
Candidate public interface: [API/component/route/module boundary]
Constraints: [security/reliability/scalability/delivery]

Update agent/design-tree.md and agent/ubiquitous-language.md if needed.
Present the plan for approval. Do not implement yet. 
If the plan contains more than 10 deliverables, create a plan.md file in the root directory, outlining the list of tasks to be done.
```

After the agent responds, review the design. If it is coherent, proceed. If not, ask it to revise the design tree first.

Use this after the initial design specification is reviewed and accepted:

```text
Implement the complete application from the approved initial design specification.

Use agent/task-routing.md and the adding-features workflow.
Implement one safe internal step at a time.
Run the formatter command, narrow checks, then ./scripts/check.sh.
For web UI behavior, verify with Playwright MCP.
Do not use sub-agents unless I explicitly ask for them.

Final response: what changed, checks run/skipped, tests/manifest changed, agent docs/ADRs updated, and whether temporary session state was cleared.
```

If you want to use sub-agents, add `Use sub-agents.` to the above prompt.

After the first pass, review missing workflow gaps and continue one safe internal step at a time until complete.

## 7. Per-Feature Developer Workflow

For every feature, do this:

1. Ask the agent to plan the feature first.
2. Review and ratify the plan.
3. Ask the agent to implement the approved plan.
4. The agent manages any step-by-step bookkeeping internally, runs the formatter, narrow checks, and `./scripts/check.sh`, then clears temporary state when done.
5. If tests changed intentionally, verify the manifest changed too.
6. The agent updates `agent/` docs or ADRs only when durable knowledge changed.

Internal session state:

Feature-step bookkeeping is an internal agent mechanism. Developers should not have to create, review, or maintain feature-slice ledgers.

Agents may use gitignored `agent/session-state.md` when a feature has multiple steps or may be interrupted. The file must contain only the smallest resume state needed for the current session.

When the feature is complete, the agent must clear `agent/session-state.md`. Only durable decisions move into `agent/design-tree.md`, `agent/architecture.md`, `agent/ubiquitous-language.md`, or an ADR.

Feature planning prompt:

```text
Feature:
[What the user can now do.]

Expected behavior:
- [Happy path]
- [Edge case]

Use agent/task-routing.md and the planning workflow.
Present the plan for my approval. Do not implement yet.
```

If you want to use sub-agents, add `Use sub-agents.` to the above prompt.

Feature implementation prompt after approval:

```text
Implement the approved feature plan.

Use agent/task-routing.md and the adding-features workflow.
Manage implementation steps internally in agent/session-state.md if needed.
Run the formatter command, narrow checks, then ./scripts/check.sh.
Clear temporary session state when the feature is complete.
Do not weaken tests. If tests change intentionally, update the test manifest.
Do not use sub-agents unless I explicitly ask for them.
```

If you want to use sub-agents, add `Use sub-agents.` to the above prompt.

Follow-up prompt to continue feature work:

```text
Continue the approved feature implementation.

Use agent/task-routing.md and the adding-features workflow.
Resume from agent/session-state.md if present.
Implement only the next safe internal step.
Run the formatter command, narrow checks, then ./scripts/check.sh.
If blocked, keep the smallest resume note in agent/session-state.md and stop.

Do not weaken tests.
If tests change intentionally, run ./scripts/update-test-manifest.sh and explain why.
```

Follow-up prompt to repair or resume interrupted work:

```text
Resume the approved feature implementation.

Use agent/session-state.md if present.
Repair or implement only the next safe internal step.
Use actual tool output as the source of truth.
Run the formatter command, narrow checks, then ./scripts/check.sh.

Do not broaden scope.
Clear temporary session state if the feature is complete.
```

## 7.5 Debugging

Debugging prompt:

```text
Debug this:
[failure, error, or broken behavior]

Expected behavior:
[what should happen]

Use agent/task-routing.md and the debugging workflow.
Use session error history automatically if present.
Reproduce or inspect the failure first, fix the smallest root cause, then run narrow checks and ./scripts/check.sh.
Keep only compact current-session error summaries in agent/session-state.md and clear resolved entries.
Do not weaken tests.
```

Code explanation prompt:

```text
Explain how this works:
[feature, module, route, component, or behavior]

Use agent/task-routing.md and the explaining-codebase workflow.
Inspect only the relevant files and do not edit anything.
```

## 8. When To Use Each Skill

Use `planning` when:

- The user asks for a plan, design, approach, or breakdown.
- A feature request has no approved plan yet.

Ask:

```text
Use agent/task-routing.md and agent/skills/planning/SKILL.md. Present the plan for approval before implementation.
```

Use `adding-features` when:

- The user has ratified a feature plan.
- The approved feature plan should be implemented.

Ask:

```text
Use agent/task-routing.md and agent/skills/adding-features/SKILL.md. Implement the approved plan one internal step at a time.
```

Use `debugging` when:

- A behavior is broken.
- A command, test, or runtime flow is failing.

Ask:

```text
Use agent/task-routing.md and agent/skills/debugging/SKILL.md for this failure: [failure].
```

Debugging error history is agent-managed:

- Keep it in gitignored `agent/session-state.md`.
- Keep at most 5 compact entries.
- Store summaries, not raw logs.
- Clear resolved entries after checks pass.

Use `explaining-codebase` when:

- The user asks how code works.
- The user wants a map of a feature, module, route, or behavior.

Ask:

```text
Use agent/task-routing.md and agent/skills/explaining-codebase/SKILL.md. Do not edit files.
```

Use `grill-me` before:

- New features with unclear design.
- Architecture changes.
- Cross-context changes.
- Ambiguous bug fixes.
- Security-sensitive work.

Ask:

```text
Run agent/skills/grill-me/SKILL.md using its YAML input and output templates.
```

Use `interview-me` after:

- `grill-me` leaves an unresolved product, UX, delivery, or risk decision.
- The answer cannot be discovered from repo files, tests, config, logs, or canonical agent docs.

Ask:

```text
Run agent/skills/interview-me/SKILL.md for this unresolved grill-me decision: [decision].
Ask one question at a time and recommend a default answer.
```

Use `testing-vertical-slices` before:

- Feature implementation.
- Bug fixes with behavior impact.
- Refactors that can break behavior.

Ask:

```text
Run agent/skills/testing-vertical-slices/SKILL.md. Choose the smallest useful test level and identify the first narrow command to run.
```

Use `improving-architecture` when:

- One change touches too many files.
- Public APIs are unclear.
- Modules are shallow pass-through layers.
- Contexts are importing each other's internals.

Ask:

```text
Run agent/skills/improving-architecture/SKILL.md on [module/path]. Propose one small boundary improvement and the tests that protect it.
```

Use `tracking-entropy` when:

- Starting weekly maintenance.
- Planning a large feature.
- Seeing repeated edits in the same files.
- Deciding where refactoring is worth it.

Ask:

```text
Run agent/skills/tracking-entropy/SKILL.md with time window 12.month. Pick one hotspot and propose the smallest next refactor step.
```

### Explicit Sub-Agent Review Overlay

Use sub-agents only when the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing implementations. Otherwise, perform these reviews locally in the main agent.

Use Design Reviewer sub-agent:

- Before coding medium/high-risk implementation steps.
- After `grill-me`, before implementation.

Ask:

```text
Review feature brief + grill-me output using the review checklist.
Report blockers, risk level, and exact fixes only.
If no blockers, reply exactly: approved for implementation
```

Use Step Reviewer sub-agent:

- After narrow checks for each medium/high-risk implementation step.
- For low-risk work, every second step to reduce overhead.

Ask:

```text
Review only the current step diff + narrow-check output.
Report blockers and exact fixes only.
If no blockers, reply exactly: approved for next step
```

Use Architecture Reviewer sub-agent:

- When one implementation step spans contexts or many files.

Ask:

```text
Review for boundary drift and propose one minimal correction plus protecting test.
Do not propose broad cleanup.
```

Use Final Reviewer sub-agent:

- Before merge on medium/high-risk work.

Ask:

```text
Review full diff + changed agent docs.
Report merge blockers and exact fixes only.
If no blockers, reply exactly: approved for merge
```

Speed notes when sub-agents are explicitly requested:

- Keep reviewer outputs blocker-only to reduce token and triage time.
- Start Slice Reviewer right after narrow checks while broader checks continue.
- Skip reviewer layers on tiny low-risk changes.

## 8.5 Worktree Branches For Parallel Agent Runs

Use Git worktrees when you explicitly want two or three agents to try competing implementations from the same base branch.

Best targets:

- Initial project implementation after the design spec is accepted.
- Medium/high-risk features.
- Ambiguous bug fixes.
- Entropy hotspot refactors.
- Competing architecture boundary designs.

Avoid worktrees for tiny edits.

### Create Variants

Start clean:

```bash
git fetch origin
git status --short
BASE=origin/main
REPO="$(basename "$(pwd)")"
WT_ROOT="../${REPO}.worktrees"
mkdir -p "$WT_ROOT"
```

Create one branch and one worktree per attempt:

```bash
git worktree add -b agents/<task-slug>-a "$WT_ROOT/<task-slug>-a" "$BASE"
git worktree add -b agents/<task-slug>-b "$WT_ROOT/<task-slug>-b" "$BASE"
git worktree add -b agents/<task-slug>-c "$WT_ROOT/<task-slug>-c" "$BASE"
```

Existing remote branch:

```bash
git fetch origin
git worktree add --track -b <branch-name> "$WT_ROOT/<branch-name>" origin/<branch-name>
```

Useful defaults:

```bash
git config --global worktree.guessRemote true
git config --global checkout.defaultRemote origin
```

### Hydrate Each Copy

In each worktree:

```bash
cd "$WT_ROOT/<task-slug>-a"
./agent/scripts/agent-doctor.sh
./scripts/check.sh
```

Then run the project dependency setup command. Copy only local non-production environment files if needed:

```bash
cp /path/to/main-worktree/.env.local .env.local
```

Do not commit secrets.

### Agent Prompt Shape

```text
You are working in ../<repo>.worktrees/<task-slug>-a on branch agents/<task-slug>-a.

Implement one safe internal step for:
[feature brief]

Variant angle:
[smallest implementation | strongest type boundary | architecture cleanup first]

Read canonical files under agent/ as needed.
Do not touch other worktrees.
Run the formatter command after code edits, then narrow checks, then ./scripts/check.sh.
Final response must include changed files, checks run, checks skipped, tests changed, manifest changed, and agent/ docs updated.
```

### Compare Variants

Collect evidence:

```bash
git -C "$WT_ROOT/<task-slug>-a" status --short
git -C "$WT_ROOT/<task-slug>-a" diff --stat "$BASE"...HEAD
git -C "$WT_ROOT/<task-slug>-a" diff "$BASE"...HEAD
```

Chooser prompt:

```text
Compare variants A, B, and C against the feature brief.

Choose the winner using:
1. Correct behavior and passing checks.
2. Smallest coherent public interface.
3. Least boundary drift.
4. Behavior tests without weakened existing tests.
5. Lowest future context cost.

Return winner, rejected alternatives, exact files/commits to keep, and cleanup needed.
```

### Integrate And Clean Up

Push the winner:

```bash
git -C "$WT_ROOT/<task-slug>-a" push -u origin agents/<task-slug>-a
```

Or merge locally into an integration branch:

```bash
git switch -c integrate/<task-slug> origin/main
git merge --no-ff agents/<task-slug>-a
./scripts/check.sh
```

Remove losing worktrees through Git:

```bash
git worktree list
git worktree remove "$WT_ROOT/<task-slug>-b"
git worktree remove "$WT_ROOT/<task-slug>-c"
git worktree prune
```

Delete losing branches only after review:

```bash
git branch -D agents/<task-slug>-b
git branch -D agents/<task-slug>-c
git push origin --delete agents/<task-slug>-b
git push origin --delete agents/<task-slug>-c
```

Notes:

- Git refuses to check out the same branch in two worktrees. Give every agent attempt its own branch.
- Use `git worktree remove`; do not manually delete worktree directories unless you also run `git worktree prune`.
- If the winning branch intentionally changed tests, run `./scripts/update-test-manifest.sh` before the final `./scripts/check.sh`.
- After a GitHub pull request merges, delete the head branch unless another open pull request still uses it as a base.
- References: [Git worktree docs](https://git-scm.com/docs/git-worktree.html), [GitHub branch docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-branches).

## 9. Weekly Maintenance

Run:

```bash
./agent/scripts/entropy-hotspots.sh
```

Then ask an agent:

```text
Do not implement new features or refactors.

Run a long-term maintenance audit from the current changed files and entropy data.

Use:
- agent/task-routing.md
- agent/skills/tracking-entropy/SKILL.md
- agent/skills/improving-architecture/SKILL.md where boundary cleanup is relevant
- agent/skills/frontend-design/SKILL.md where UI/CSS cleanup is relevant

Read:
- git status --short
- git diff --stat
- git diff
- output from ./agent/scripts/entropy-hotspots.sh
- relevant tests and generated-output config

Identify everything that could potentially be removed, split, or refactored:
- dead selectors
- repeated CSS patterns
- oversized rendering functions or components that should be split
- duplicated domain or formatting logic
- shallow pass-through modules
- boundary leaks or imports that should move behind public entry points
- generated artifacts that should not be hand-edited
- stale files, unused fixtures, or obsolete docs created during the product run
- tests missing for known regressions or fragile user-visible behavior

Return one complete maintenance backlog, not just one slice.

For each candidate include:
- file/path
- exact smell or risk
- why it is safe or unsafe to change
- proposed removal/refactor
- protecting test/check or missing regression test
- whether an ADR/design-tree update is needed
- risk level: low, medium, or high

Then group the backlog into:
1. Safe removals
2. Safe extractions
3. Needs regression test first
4. Needs design or ADR decision
5. Do not touch because generated or externally owned

Finally recommend the smallest implementation order for the whole backlog, but do not edit files.
```

If you approve part or all of the backlog, ask the agent to implement the selected group in small checked steps and run:

```bash
./scripts/check.sh
```

## 10. ADR Rule

Create an ADR in `agent/adr/` when a decision affects future work.

Use ADRs for:

- Bounded context changes.
- Public interface changes.
- Persistence shape changes.
- Adapter contracts.
- Test strategy changes.
- Security model changes.
- Naming conventions across contexts.

Do not write ADRs for tiny implementation details.

## 11. Daily Commands

Use these most often:

```bash
./scripts/check.sh
```

Run all deterministic checks.

```bash
./scripts/check-project.sh
```

Run the project-specific formatter check, linter, typecheck, and tests configured for this codebase.

```bash
./scripts/check-tests-unchanged.sh
```

Check whether the configured test scope changed.

```bash
./scripts/update-test-manifest.sh
```

Approve intentional test changes by refreshing the manifest.

```bash
./agent/scripts/agent-doctor.sh
```

Check that the agent control plane and generated shims are present and synced.

```bash
./agent/scripts/sync-agent-env.sh
```

Regenerate tool-specific instruction files from `agent/tool-instruction-template.md`.

```bash
./agent/scripts/entropy-hotspots.sh
```

Find files that changed most often in Git history.

```bash
./agent/scripts/module-doctor.sh
```

Validate all sub-module agent structures (if any exist).

```bash
git worktree list
```

List active worktrees and their checked-out branches.

```bash
git worktree remove ../<repo>.worktrees/<task-slug>-b
```

Remove a completed or rejected worktree.

```bash
test ! -s agent/session-state.md
```

Check that no temporary session state remains after completed work.

## 12. What To Check Before Merging

Before merge, require:

1. `./scripts/check.sh` passes.
2. `./agent/scripts/agent-doctor.sh` passes.
3. The agent final response lists checks run and skipped.
4. Any intentional test changes include an updated manifest.
5. New domain terms are in `agent/ubiquitous-language.md`.
6. Boundary changes are in `agent/architecture.md`.
7. Durable decisions have ADRs.
8. No hidden rules exist only in chat.
9. Sub-agent review is present only if the user explicitly requested sub-agents.
10. If worktrees were used, the winning branch is identified and rejected worktrees are removed or intentionally kept.
11. `scripts/check-project.sh` includes formatter check mode and lint for the current project stack.
12. `agent/session-state.md` is empty or absent unless work is intentionally blocked.

## 13. Quick Recovery

If an agent makes a messy change:

1. Stop feature expansion.
2. Run `./scripts/check.sh`.
3. Ask the agent to repair only from tool output.
4. If design drift caused the issue, run `grill-me`.
5. If tests changed unexpectedly, run `./scripts/check-tests-unchanged.sh` and inspect the diff.
6. If one module is absorbing too much change, run `tracking-entropy` and then `improving-architecture`.
7. If `agent/session-state.md` contains stale notes, either resume from them or clear them after extracting any durable decision.

## 14. Sub-Module Agent Structure

Use this when a project grows to 3+ independently complex bounded contexts that each need their own design decisions, domain language, and testing commands.

### When To Use

- Monorepo with 3+ independently deployable services or packages.
- Sub-modules with different tech stacks or domain vocabularies.
- A single root `agent/` has become too broad for agents to load efficiently.

### When NOT To Use

- Projects with fewer than 3 bounded contexts (the root `agent/` is sufficient).
- Sub-modules that share the same domain language, architecture, and test commands.

The `init-module-agent.sh` script enforces this: it refuses to create a sub-module agent unless 3+ bounded contexts are declared in root `agent/architecture.md`.

### Structure

```text
repo-root/
  agent/                          ← root (global rules, shared language, skills, scripts)
  modules/
    billing/
      agent/                      ← module-level (billing-specific decisions)
        module-context.md
        project-brief.md
        design-tree.md
        architecture.md
        ubiquitous-language.md
        testing-policy.md
        adr/
      src/
    identity/
      agent/
      src/
    notifications/
      agent/
      src/
```

### What Lives Where

| Concern             | Root `agent/`                      | Module `agent/`         |
| ------------------- | ------------------------------------ | ------------------------- |
| Engineering rules   | ✓ (authoritative)                   | inherits                  |
| Security policy     | ✓ (authoritative)                   | inherits                  |
| Skills              | ✓ (shared)                          | inherits                  |
| Scripts             | ✓ (shared)                          | inherits                  |
| Project brief       | whole-system goal                    | module goal               |
| Design tree         | cross-module decisions               | module-internal decisions |
| Architecture        | module map + cross-module boundaries | internal module structure |
| Ubiquitous language | shared terms                         | module-local terms        |
| Testing policy      | root gate commands                   | module-specific commands  |
| ADRs                | cross-module decisions               | module-internal decisions |

### Create A Sub-Module Agent

```bash
mkdir -p modules/billing
./agent/scripts/init-module-agent.sh modules/billing billing "Plans, invoices, subscription state"
```

Then fill the generated files with real content and update root `agent/architecture.md`.

### Validate All Modules

```bash
./agent/scripts/module-doctor.sh
```

This warns if fewer than 3 module agents exist.

### Agent Prompt For Module Work

```text
Working in: modules/billing

[feature/bug/plan request]

Read modules/billing/agent/module-context.md for scope and precedence.
Use the module's agent/ files for module-specific context.
Use root agent/ for skills, rules, and scripts.
Run the module's check command first, then ./scripts/check.sh.
```

### Cross-Module Feature Prompt

```text
This feature touches modules/billing and modules/identity.

Read each module's agent/module-context.md.
Changes to module internals follow that module's agent/ files.
Interface changes between modules follow root agent/architecture.md.
New shared terms go in root agent/ubiquitous-language.md.
If a boundary changes, create a root-level ADR.
```

### Precedence

1. Explicit user instructions.
2. Module `agent/` files (for module-specific concerns).
3. Root `agent/` files (for shared rules, skills, scripts, security).
4. Existing code and conventions.

### Managing Over Time

Adding a module:

```bash
mkdir -p modules/new-module
./agent/scripts/init-module-agent.sh modules/new-module new-module "Domain description"
```

Splitting a module: create the new module agent, move relevant ADRs, update both modules and root `architecture.md`, create a root ADR.

Merging modules: choose the surviving module, merge design-tree and language, remove the defunct `agent/`, update root `architecture.md`, create a root ADR.
