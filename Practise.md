# Putting it together

The goal is not to make agents write more code. The goal is to make agents produce code that remains understandable, testable, and easy to change after the first generation.

This is the practical gameplan for building a sophisticated working application with agents. We use the idea of shared design concept, skills, ubiquitous language, feedback loops, entropy control, modularity, TDD, coupling management, and DDD.

## The Core Operating Rule

Agents are fast, but speed only helps when the feedback loops are stronger than the generation loop.

Every agent task should therefore follow this shape:

1. Clarify the design concept.
2. Write or update the smallest useful design artifact.
3. Implement one internal feature slice.
4. Run deterministic checks.
5. Repair based on tool output.
6. Record the design decision if it changes architecture or language.

Do not ask the agent to "build the app" in one large pass. Ask it to build one behavior, through one module boundary, with one testable outcome.

## Step 1: Create The Agent Control Plane

Add an `agent/` directory to the repo. This becomes the shared source of truth for all coding agents.

Recommended structure:

```text
agent/
  README.md
  project-brief.md
  design-tree.md
  ubiquitous-language.md
  architecture.md
  testing-policy.md
  security-policy.md
  agent-rules.md
  task-routing.md
  tool-instruction-template.md
  mcp.json
  skills/
    planning/
      SKILL.md
    adding-features/
      SKILL.md
    debugging/
      SKILL.md
    explaining-codebase/
      SKILL.md
    grill-me/
      SKILL.md
    interview-me/
      SKILL.md
    testing-vertical-slices/
      SKILL.md
    improving-architecture/
      SKILL.md
    tracking-entropy/
      SKILL.md
  scripts/
    agent-doctor.sh
    sync-agent-env.sh
    entropy-hotspots.sh
  adr/
    0001-record-architecture-decisions.md
```

Why this matters: agents need a stable memory layer that lives in the repo, not in one person's chat history or local tool configuration.

Keep these files short enough to be loaded frequently. Move long references, examples, schemas, and checklists into separate files that agents load only when needed. Use `agent/task-routing.md` as the retrieval layer that maps the user's current intent to one task workflow.

Then generate tool-specific instruction files from the canonical `agent/` files. Common targets:

```text
AGENTS.md
CLAUDE.md
.cursor/rules/agent-rules.md
.github/copilot-instructions.md
.codex/AGENTS.md
```

Treat these as generated shims. The real source of truth stays in `agent/`.

### Tool-Specific Instruction Prompt

Add this exact prompt to `agent/tool-instruction-template.md`, then copy it into each tool-specific instruction file, including `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`, and `.codex/AGENTS.md`.

The prompt is deliberately short. Its job is not to repeat every rule. Its job is to make each agent load the canonical repo files, obey their precedence, and keep its work inside deterministic feedback loops.

```md
# Agent Operating Instructions

This tool-specific instruction file is a generated shim. Do not edit this copy manually. Update `agent/tool-instruction-template.md` and rerun `agent/scripts/sync-agent-env.sh`.

You are working in this repository as an implementation agent. Treat the repository files as the source of truth. Do not rely on hidden chat history, memory, or assumptions when a repo-owned instruction file answers the question.

## Instruction Precedence

1. Follow explicit user instructions for the current task.
2. Follow the canonical files in `agent/`.
3. Follow this tool-specific shim.
4. Follow existing code, tests, and local conventions.

If this shim conflicts with files under `agent/`, treat this shim as stale, follow the `agent/` files, and mention the conflict in your final response.

## Required Context Before Editing

Before changing code or tests, read `agent/task-routing.md`, classify the current task, and load only the matching workflow from `agent/skills/<skill-name>/SKILL.md`.

Then read the smallest relevant set of canonical files requested by that workflow:

- `agent/project-brief.md`
- `agent/design-tree.md`
- `agent/architecture.md`
- `agent/ubiquitous-language.md`
- `agent/testing-policy.md`
- `agent/agent-rules.md`

Load additional files only when they are relevant to the task. Keep context focused.

## Skill Use

Skills live under `agent/skills/<skill-name>/SKILL.md`. Use a skill when its name or purpose matches the task.

Task workflows:

- Use `planning` for plans, designs, approaches, and feature planning gates.
- Use `adding-features` for feature implementation after a user-ratified plan.
- Use `debugging` for bugs, failures, regressions, exceptions, and failing checks.
- Use `explaining-codebase` for codebase walkthroughs and explanations without edits.

Supporting skill triggers:

- Use `grill-me` before non-trivial features, architecture changes, cross-context changes, or ambiguous bug fixes.
- Use `interview-me` only after `grill-me` leaves unresolved user judgment that cannot be answered from repo inspection.
- Use `testing-vertical-slices` for feature work and bug fixes that need behavior verification.
- Use `improving-architecture` when a change exposes shallow modules, unclear ownership, repeated coupling, or hard-to-test structure.
- Use `tracking-entropy` when asked to assess maintainability, hotspots, churn, complexity, or refactoring priority.

When using a skill, read its `SKILL.md`, follow its process, and load only the referenced supporting files needed for the current task.

Do not use sub-agents unless the user explicitly asks for sub-agents, parallel agents, reviewer agents, or competing agent implementations.

## Default Work Loop

For every implementation task:

1. Restate the requested behavior and identify the bounded context.
2. Identify the intended public interface and the files likely to change.
3. Add or identify the smallest test or deterministic check that proves the behavior.
4. Implement one internal feature slice at a time.
5. Run the narrowest relevant check first, then the broader relevant suite.
6. Repair based on actual tool output, not guesswork.
7. Update `agent/ubiquitous-language.md`, `agent/design-tree.md`, `agent/architecture.md`, or `agent/adr/` if the change alters domain language, boundaries, or durable design decisions.

For feature implementation, an approved plan is mandatory. If no approved plan exists, produce the plan first, present it to the user, and stop. Do not implement until the user ratifies the plan.

Feature-slice bookkeeping is internal. Use gitignored `agent/session-state.md` only when interruption or resume support is needed, and clear it when the feature is complete. Do not store temporary slice state in canonical files.

## Engineering Rules

- Prefer existing project patterns over new abstractions.
- Keep public interfaces small and explicit.
- Do not import another bounded context's internals.
- Put external systems behind adapters; do not leak API clients, ORM records, HTTP objects, or UI state into domain logic.
- Use domain names from `agent/ubiquitous-language.md`; add new domain terms when needed.
- Write types or interfaces before implementation when the language supports it.
- Do not weaken tests to make implementation pass.
- Do not edit unrelated files.
- Do not store secrets in code, tests, logs, prompts, or instruction files.

## Verification

Run the checks required by `agent/testing-policy.md` and the local toolchain. If a required check cannot run, explain why and state the risk.

Your final response must include:

- What changed.
- Which checks ran.
- Which checks were skipped or unavailable.
- Any design files, glossary entries, or ADRs updated.
```

## Step 2: Write The Minimum Useful Instruction Files

Create these files before serious implementation starts.

### `agent/task-routing.md`

Purpose: keep the default prompt small by routing the user's current intent to one workflow.

Use it to map:

- Planning requests to `agent/skills/planning/SKILL.md`.
- Feature requests to `agent/skills/adding-features/SKILL.md`.
- Debugging requests to `agent/skills/debugging/SKILL.md`.
- Explanation requests to `agent/skills/explaining-codebase/SKILL.md`.

Rule: load exactly one task workflow first. Load supporting skills and canonical files only when that workflow asks for them.

Feature gate: if the user asks for feature implementation and no approved plan exists, the agent must produce the plan, present it to the user, and stop. Implementation starts only after user ratification.

### Temporary Vs Durable Agent State

Purpose: prevent context bloat in canonical agent files.

Temporary state belongs in gitignored `agent/session-state.md` and should be removed as soon as it is no longer needed:

- Internal feature-slice checklists.
- Current failing command excerpts.
- Resume notes for blocked work.
- Scratch reviewer notes.
- Worktree variant comparison notes.

Durable state belongs in canonical files only when it changes future implementation:

- `agent/design-tree.md` for open or settled design decisions.
- `agent/architecture.md` for bounded contexts, ownership, public interfaces, adapters, and forbidden imports.
- `agent/ubiquitous-language.md` for domain terms that should appear in prompts, code, or tests.
- `agent/adr/*` for decisions that future agents must preserve.

Cleanup rule: when a feature, debug repair, or refactor finishes, remove temporary session state. If a temporary note revealed durable knowledge, compress it into the appropriate canonical file and delete the scratch detail.

### `agent/project-brief.md`

Purpose: define what the application is trying to become.

Include:

- Product goal.
- Primary users.
- The 3 to 5 workflows that must feel excellent.
- Non-goals.
- External systems the app depends on.
- What "done" means for a feature.

Template:

```md
# Project Brief

## Product Goal

Build [application] for [users] so they can [core outcome].

## Primary Workflows

1. [Workflow name]: [user goal]
2. [Workflow name]: [user goal]
3. [Workflow name]: [user goal]

## Non-Goals

- [Explicit thing not being built yet]

## External Systems

- [API/database/service] used for [reason]

## Definition Of Done

A feature is complete only when it has:

- A small design note or updated design artifact.
- Types/interfaces for the new boundary.
- Tests for the intended behavior and at least one edge case.
- Passing formatter, linter, typecheck, and relevant tests.
- No new illegal imports across bounded contexts.
```

### `agent/design-tree.md`

Purpose: keep the shared design concept visible.

This is not a giant upfront plan. It is a living decision tree that improves through implementation.

Use this format:

```md
# Design Tree

## Current Design Concept

[One paragraph describing the organizing idea of the system.]

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |
| [Question] | [A, B, C] | [A] | [Reason] |

## Settled Decisions

| Decision | Choice | Date | ADR |
| --- | --- | --- | --- |
| [Question] | [Choice] | [YYYY-MM-DD] | [ADR link] |

## Pressure Points

- [Constraint, ambiguity, or tradeoff that keeps affecting implementation.]
```

Agent rule: before making architectural changes, the agent must update `Open Decisions` or create an ADR.

### `agent/ubiquitous-language.md`

Purpose: make domain vocabulary explicit so agents do not invent sloppy names.

Use this table:

```md
# Ubiquitous Language

| Business Term | Technical Symbol | Definition | Constraints | Avoid |
| --- | --- | --- | --- | --- |
| Account | `Account` | Organization or person that owns work in the app. | Has stable identity. | `UserAccount`, `CustomerData` |
| Member | `Member` | Human user inside an account. | Belongs to exactly one account. | `User`, unless auth-specific |
```

Practical rule: if a new domain noun appears in code, it should be added here in the same PR.

### `agent/architecture.md`

Purpose: tell agents where code belongs.

Include:

- Bounded contexts.
- Module responsibilities.
- Public interfaces.
- Forbidden imports.
- Where adapters live.
- Where domain logic must not leak.

Example:

```md
# Architecture

## Bounded Contexts

| Context | Owns | Does Not Own |
| --- | --- | --- |
| Billing | Plans, invoices, subscription state | Authentication, notification delivery |
| Identity | Login, sessions, members, roles | Product billing rules |

## Boundary Rules

- Contexts may import from their own public entry point.
- Contexts must not import another context's internal files.
- External APIs are accessed through adapters, not directly from domain logic.
- Domain objects must not depend on HTTP request objects, ORM records, or UI state.

## Public Interface Rule

Each context exposes one public entry point:

- TypeScript: `src/<context>/index.ts`
- Python: `src/<context>/__init__.py`
- Go: `internal/<context>` plus explicit exported symbols
```

### `agent/testing-policy.md`

Purpose: prevent agents from treating tests as optional or moving the goal posts.

Include:

- Test pyramid expectations.
- What counts as a unit.
- What to mock.
- What not to mock.
- When integration and E2E tests are required.
- Whether tests may be edited during a bug fix.

Recommended policy:

```md
# Testing Policy

## Default Loop

1. Add or identify the failing behavior.
2. Write the smallest test that captures it.
3. Implement the fix.
4. Run the narrow test.
5. Run the broader relevant suite.

## Test Modification Rule

Existing tests may not be weakened to make implementation pass.

During bug fixes, tests can be added. Existing test assertions can be changed only if the design artifact or ADR explains why the expected behavior changed.

## What To Mock

- Mock external services, clocks, randomness, payment providers, email, and network calls.
- Do not mock domain logic inside the same bounded context.

## Required Checks

- Formatter
- Linter
- Typecheck
- Unit tests
- Relevant integration tests
- E2E smoke test for user-facing workflow changes
```

### `agent/agent-rules.md`

Purpose: make the agent's day-to-day behavior explicit.

Recommended rules:

```md
# Agent Rules

## Before Coding

- Read `agent/project-brief.md`, `agent/design-tree.md`, `agent/architecture.md`, and `agent/ubiquitous-language.md`.
- Identify the bounded context being changed.
- State the intended public interface.
- Run the `grill-me` skill for non-trivial changes.

## While Coding

- Work in one internal feature slice at a time.
- Prefer existing project patterns over new abstractions.
- Define types and interfaces before implementation.
- Keep public interfaces small.
- Do not reach into another context's internals.
- Do not weaken tests to pass implementation.

## Before Finishing

- Run formatter, linter, typecheck, and relevant tests.
- Explain which checks ran and which did not.
- Update the glossary, design tree, or ADRs if the design changed.
- Clear `agent/session-state.md` when temporary implementation state is no longer needed.
```

## Step 3: Add Skills That Encode Repeatable Work

Skills should be small, named by capability, and loaded only when relevant. Do not make one giant "coding" skill.

### Task Workflow: `planning`

Create `agent/skills/planning/SKILL.md`.

Use when the user asks for a plan, design, approach, or when a feature request has no approved plan yet.

The workflow should:

1. Restate the requested outcome.
2. Load only the canonical files needed for the bounded context.
3. Identify public interface, likely files, checks, and design artifacts.
4. Split larger work into internal feature slices without exposing slice bookkeeping to the user.
5. Run `grill-me` locally for risky or ambiguous work.
6. Present the plan and wait for user ratification before implementation.

### Task Workflow: `adding-features`

Create `agent/skills/adding-features/SKILL.md`.

Use for feature implementation only after the user has ratified a plan.

Hard gate:

- If no approved plan exists, run `planning`, present the plan, and stop.
- Do not edit implementation code until the user ratifies the plan.
- After ratification, implement one internal feature slice at a time.
- Track temporary feature-slice state in `agent/session-state.md`, not canonical files.
- Clear `agent/session-state.md` when the feature is complete.

### Task Workflow: `debugging`

Create `agent/skills/debugging/SKILL.md`.

Use when the user reports a bug, failing check, exception, regression, or broken behavior.

The workflow should reproduce or inspect the failure first, identify the smallest behavior check that proves the fix, repair from actual tool output, and avoid broad rewrites.

Session error history:

- Use `agent/session-state.md` for current-session error summaries only.
- Keep at most 5 entries.
- Keep each entry to about 10 lines or fewer.
- Store summaries, not raw logs.
- Redact secrets, tokens, credentials, raw production data, and personal data.
- Clear resolved entries after the bug is fixed or no longer relevant.

### Task Workflow: `explaining-codebase`

Create `agent/skills/explaining-codebase/SKILL.md`.

Use when the user asks how code works. It should inspect the smallest relevant file set, explain public interfaces before internals, and avoid file edits.

### Skill 1: `grill-me`

Create `agent/skills/grill-me/SKILL.md`.

```md
# Grilling Design

Use before implementation of non-trivial features, architecture changes, or ambiguous bug fixes.

## Process

1. Restate the requested outcome in one paragraph.
2. Identify the bounded context and public interface.
3. List the main design options.
4. Critique the current plan for:
   - Reliability
   - Context management
   - Security
   - Scalability
   - Testability
   - Coupling
5. Ask: "What assumption would make this implementation wrong?"
6. Revise the plan.
7. Write the first internal implementation step.

## Output

- Chosen approach
- Rejected alternatives
- Risks
- Checks to run
- Files likely to change
```

Actionable insight: make the agent argue against its own first plan before it edits files. This catches vague boundaries and hidden coupling early.

### Skill 2: `interview-me`

Create `agent/skills/interview-me/SKILL.md`.

```md
# Interview Me

Use only when `grill-me` leaves an unresolved decision that depends on user judgment and cannot be answered from repository exploration.

## Process

1. State the unresolved decision in one sentence.
2. Explore the repository first if the answer might be discoverable.
3. Ask exactly one focused question.
4. Provide the recommended default answer.
5. Wait for the user's answer before asking the next question.
6. Return the resolved decision to the calling workflow.
```

Actionable insight: keep `grill-me` as the structured critique and use `interview-me` only for conversational decisions that truly require the developer.

### Skill 3: `testing-vertical-slices`

Create `agent/skills/testing-vertical-slices/SKILL.md`.

```md
# Testing Vertical Slices

Use when implementing a feature or bug fix.

## Process

1. Define the behavior in domain language.
2. Pick the smallest useful test level:
   - Unit for pure domain rules.
   - Integration for persistence, adapters, or cross-module behavior.
   - E2E for critical user workflows.
3. Write or identify the failing test first.
4. Implement only enough code to pass it.
5. Refactor after the test is green.
6. Add one edge-case test for the behavior the agent was most likely to miss.

## Rules

- Do not mock code from the same bounded context.
- Do mock external systems.
- Do not weaken existing tests without updating a design artifact.
```

Actionable insight: agents behave better when the unit of work is a tested behavior, not a file list.

### Skill 4: `improving-architecture`

Create `agent/skills/improving-architecture/SKILL.md`.

```md
# Improving Architecture

Use when code feels hard to change, a feature crosses too many files, or a module boundary is unclear.

## Process

1. Identify the friction point.
2. Name the domain concept being hidden by the current structure.
3. Find shallow modules that only pass arguments through.
4. Propose a smaller public interface.
5. Move implementation detail behind that interface.
6. Add or update boundary tests.
7. Record the decision in an ADR if the boundary changes.

## Output

- Current problem
- Proposed boundary
- Public API
- Internal files
- Tests protecting the boundary
```

Actionable insight: the best refactors for agents are boundary refactors. They reduce the amount of context future agents need.

### Skill 5: `tracking-entropy`

Create `agent/skills/tracking-entropy/SKILL.md`.

```md
# Tracking Entropy

Use weekly, before large features, or when a file keeps getting changed by unrelated tasks.

## Process

1. Run `agent/scripts/entropy-hotspots.sh`.
2. Identify files with both high churn and high complexity.
3. For the top hotspot, ask:
   - Which concepts are mixed together?
   - Which imports reveal illegal coupling?
   - Which tests would protect a split?
4. Create one small refactoring issue.
5. Do not refactor opportunistically inside unrelated feature work.
```

Actionable insight: AI increases entropy when every feature touches the same central files. Track churn so refactoring work is aimed at the real risk.

## Step 4: Connect Deterministic Tools And MCP Servers

Agents need deterministic tools more than they need longer prompts.

Create `agent/mcp.json` as the desired MCP inventory. Exact server names vary by agent platform, but this is the target capability set:

```json
{
  "required": [
    {
      "name": "filesystem",
      "purpose": "Read and edit repository files with explicit workspace limits"
    },
    {
      "name": "git",
      "purpose": "Inspect diffs, history, branches, and changed files"
    },
    {
      "name": "fetch",
      "purpose": "Fetch external documentation as markdown when current docs are required"
    },
    {
      "name": "browser",
      "purpose": "Run Playwright or Puppeteer checks for web UI behavior"
    }
  ],
  "optional": [
    {
      "name": "database-readonly",
      "purpose": "Inspect schemas and safe sample data without mutation"
    },
    {
      "name": "logs-readonly",
      "purpose": "Read production errors from Sentry, Datadog, CloudWatch, or equivalent"
    },
    {
      "name": "docs-search",
      "purpose": "Search internal docs, ADRs, runbooks, and product specs"
    }
  ]
}
```

Practical security rules:

- Give agents read-only access by default.
- Use separate credentials for agent tooling.
- Never place secrets in instruction files.
- Prefer local `.env.example` plus a secret manager over shared `.env` files.
- For database MCP access, start with schema-only or read-only mode.
- Require human approval for migrations, destructive shell commands, production writes, and dependency upgrades.

## Step 5: Standardize Local Commands

Agents need one obvious command for each feedback loop.

Add these package scripts, Make targets, or task runner commands:

```text
format
lint
typecheck
test
test:unit
test:integration
test:e2e
check
dev
build
```

`check` should run the normal pre-PR gate:

```text
format -> lint -> typecheck -> unit tests -> relevant integration tests
```

For web apps, add a Playwright smoke test for the most important workflow. This gives agents visual/runtime feedback instead of relying only on static code.

## Step 6: Add Practical Scripts

### `agent/scripts/agent-doctor.sh`

Purpose: quickly tell whether an environment is ready for agent work.

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Checking agent workspace..."

test -f agent/project-brief.md
test -f agent/design-tree.md
test -f agent/ubiquitous-language.md
test -f agent/architecture.md
test -f agent/testing-policy.md
test -f agent/agent-rules.md
test -f agent/task-routing.md
test -f agent/tool-instruction-template.md
test -f agent/skills/planning/SKILL.md
test -f agent/skills/adding-features/SKILL.md
test -f agent/skills/debugging/SKILL.md
test -f agent/skills/explaining-codebase/SKILL.md
test -f agent/skills/interview-me/SKILL.md

command -v git >/dev/null
grep -qxF "agent/session-state.md" .gitignore

echo "Agent instruction files present."
echo "Git available."
echo "Now run the project-specific check command."
```

### `agent/scripts/sync-agent-env.sh`

Purpose: sync repo-owned instructions into local agent-specific locations.

Keep the source of truth in `agent/`. The script should copy from the repo into each tool's expected config directory, never the other way around.

Example:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHIM="$ROOT/agent/tool-instruction-template.md"

mkdir -p "$ROOT/.codex"
mkdir -p "$ROOT/.cursor/rules"
mkdir -p "$ROOT/.github"

cp "$SHIM" "$ROOT/AGENTS.md"
cp "$SHIM" "$ROOT/CLAUDE.md"
cp "$SHIM" "$ROOT/.codex/AGENTS.md"
cp "$SHIM" "$ROOT/.cursor/rules/agent-rules.md"
cp "$SHIM" "$ROOT/.github/copilot-instructions.md"

echo "Synced generated tool instruction shims from agent/ into local agent config files."
```

Practical note: if multiple tools need small format differences, keep `agent/tool-instruction-template.md` as the shared shim and generate tool-specific versions from it. Do not manually maintain five divergent instruction files.

### `agent/scripts/entropy-hotspots.sh`

Purpose: find files that deserve architectural attention.

```bash
#!/usr/bin/env bash
set -euo pipefail

SINCE="${1:-12.month}"

git log --format=format: --name-only --since="$SINCE" \
  | sed '/^$/d' \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -20
```

Start with churn. Add complexity tooling later only if the churn list is too noisy.

### `scripts/check-tests-unchanged.sh`

Purpose: detect whether the test suite changed since the last approved test manifest.

This does not make tests impossible to edit. It makes test changes explicit, deterministic, and easy to review. The check compares files under `tests/` against a committed SHA-256 manifest at `tests/.manifest.sha256`.

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${ROOT_DIR}/tests"
MANIFEST="${TESTS_DIR}/.manifest.sha256"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

if [[ ! -d "${TESTS_DIR}" ]]; then
  printf "check-tests: no tests/ directory (skipping)\n"
  exit 0
fi

if [[ ! -f "${MANIFEST}" ]]; then
  fail "check-tests: missing ${MANIFEST}. Run scripts/update-test-manifest.sh to create it."
fi

if command -v sha256sum >/dev/null 2>&1; then
  SHA="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA="shasum -a 256"
else
  fail "check-tests: need sha256sum or shasum."
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

(
  cd "${TESTS_DIR}"
  find . -type f -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' p; do
        [[ "$p" == "./.manifest.sha256" ]] && continue
        rel="${p#./}"
        ${SHA} "$rel"
      done
) >"$tmp"

normalize() {
  awk '{print $1" "$2}' "$1"
}

if ! diff -u <(normalize "${MANIFEST}") <(normalize "$tmp") >/dev/null; then
  fail "check-tests: tests/ contents differ from manifest. If intentional, run scripts/update-test-manifest.sh and commit the updated manifest."
fi

printf "check-tests: OK (manifest matches)\n"
```

Pair it with `scripts/update-test-manifest.sh`, which is only run when a test change is intentional:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${ROOT_DIR}/tests"
MANIFEST="${TESTS_DIR}/.manifest.sha256"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

mkdir -p "${TESTS_DIR}"

if command -v sha256sum >/dev/null 2>&1; then
  SHA="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  SHA="shasum -a 256"
else
  fail "update-manifest: need sha256sum or shasum."
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

(
  cd "${TESTS_DIR}"
  find . -type f -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' p; do
        [[ "$p" == "./.manifest.sha256" ]] && continue
        rel="${p#./}"
        ${SHA} "$rel"
      done
) >"$tmp"

mv "$tmp" "${MANIFEST}"
printf "Wrote %s\n" "${MANIFEST}"
```

Expose all deterministic checks through one manual command:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT_DIR}/scripts/check-md.sh"
"${ROOT_DIR}/scripts/check-tests-unchanged.sh"
"${ROOT_DIR}/scripts/check-project.sh"

printf "OK\n"
```

Run this command whenever you want assurance that the repo still satisfies the deterministic checks:

```bash
./scripts/check.sh
```

### Add Project Formatters And Linters To `check-project.sh`

Do not add another wrapper script for formatting and linting. `./scripts/check.sh` already calls `scripts/check-project.sh`, so `check-project.sh` is the right extension point for project-specific code quality.

The standard order is:

1. Formatter check.
2. Linter.
3. Typecheck.
4. Unit/integration tests.

Use a formatter's non-mutating check mode in `check-project.sh` whenever the tool supports it. Agents may run the mutating formatter after writing code, but the deterministic gate should be able to fail in CI without silently changing files.

Recommended `scripts/check-project.sh` examples:

```bash
#!/usr/bin/env bash
set -euo pipefail

npm run format:check
npm run lint
npm run typecheck
npm test
```

```bash
#!/usr/bin/env bash
set -euo pipefail

ruff format --check .
ruff check .
pyright
pytest
```

```bash
#!/usr/bin/env bash
set -euo pipefail

test -z "$(gofmt -l .)"
go vet ./...
golangci-lint run
go test ./...
```

For agent repair loops, also record the mutating formatter command in `agent/testing-policy.md` so agents can run it immediately after code edits:

| Stack | Mutating formatter after edits | Formatter check in `check-project.sh` | Linter |
| --- | --- | --- | --- |
| TypeScript/JavaScript | `npm run format` | `npm run format:check` | `npm run lint` |
| Python | `ruff format .` | `ruff format --check .` | `ruff check .` |
| Go | `gofmt -w .` | `test -z "$(gofmt -l .)"` | `go vet ./...` and/or `golangci-lint run` |

If a project does not have a formatter or linter yet, `agent/testing-policy.md` must say `not available yet` and explain why. Once code exists, the formatter and linter should be added before relying on agents for larger feature work.

## Step 7: Enforce Boundaries With Tooling

Use the lightest tool that catches real mistakes.

For TypeScript:

- `prettier` or the framework formatter, with `format` and `format:check` package scripts.
- `strict: true` in `tsconfig.json`.
- `eslint-plugin-import` or `dependency-cruiser` to block imports into another context's internals.
- `eslint` naming rules for banned vague names like `Data`, `Manager`, `Helper`, `Util`, and `Base`.
- `fast-check` for property-based tests where invariants matter.

For Python:

- `ruff format` for formatting.
- `pyright` or `mypy` in strict mode where practical.
- `ruff` for linting and import rules.
- `pytest` for tests.
- `hypothesis` for property-based tests.
- package `__init__.py` files that expose public APIs deliberately.

For Go:

- `gofmt` for formatting.
- `go test ./...`.
- `internal/` packages for hidden implementation.
- `golangci-lint`.
- interfaces at boundaries where substitution is actually needed.

Do not add complex governance before the app has real shape. Start with typecheck, tests, and import boundaries. Add custom lint rules only after you see repeated naming or coupling failures.

## Step 8: Use The Feature Workflow Every Time

This is the default agent workflow for building one feature.

### 1. Intake

The human or lead agent writes a small feature brief:

```md
## Feature

[What user can now do.]

## Domain Language

[Terms from `agent/ubiquitous-language.md`.]

## Bounded Context

[Context being changed.]

## Expected Behavior

- [Behavior]
- [Edge case]

## Checks

- [Relevant formatter command]
- [Relevant test command]
- [Relevant typecheck/lint command]
```

### 2. Pre-flight Design Review

Run the `grill-me` skill.

Required output:

- Chosen design.
- Rejected alternatives.
- Main risk.
- Public interface.
- Test strategy.

For small changes, this can be five bullets. For architectural changes, it should update `agent/design-tree.md` or create an ADR.

#### Explicit Sub-Agent Overlay (only when requested)

Add this block only when the user explicitly asks for sub-agents, reviewer agents, parallel agents, or competing implementations. Otherwise, perform this review locally in the main agent and continue the base workflow.

Sub-agent: **Design Reviewer** (independent reviewer).

Prompt:

```text
Review the feature brief and grill-me output before coding.
Use the Step 10 review checklist only.
Report only:
- blocking issues
- risk level (low/medium/high)
- one concrete fix per blocker
If there are no blockers, reply exactly: approved for implementation
```

### 3. Type And Interface First

Before implementation, define:

- Domain types.
- Value objects for important primitives.
- Public function/class/component boundary.
- Adapter interface for external systems.

This narrows the agent's search space and gives the compiler something useful to check.

### 4. Test The Behavior

Use the smallest test that proves the behavior.

Testing choice:

- Pure rule: unit test.
- Database or adapter behavior: integration test.
- User workflow: E2E smoke test.
- Invariant-heavy logic: property-based test.

Add one edge case that targets the easiest agent mistake.

### 5. Implement One Internal Step

Rules:

- Touch the fewest bounded contexts possible.
- Keep external systems behind adapters.
- Keep domain logic away from UI, HTTP, ORM, and vendor SDK details.
- Do not create generic helpers until two or three real call sites prove the shape.
- Prefer deep modules with small public APIs.

#### Explicit Sub-Agent Escalation For Multi-Context Work (only when requested)

Use this only when the user explicitly asks for sub-agents. If an implementation step touches multiple bounded contexts, too many files, or has unclear ownership, run the same review locally unless sub-agents were requested.

Sub-agent: **Architecture Reviewer** (`improving-architecture`).

Prompt:

```text
Review this implementation step for boundary drift.
Identify:
- hidden domain concept
- boundary that should be tightened
- smallest public API change
- test that protects the boundary
Return one minimal refactor step only.
```

### 6. Run Generate-Check-Fix

The agent runs:

```text
formatter write command
formatter check
lint
typecheck
targeted test
broader relevant test
```

The mutating formatter command should run immediately after code is written, before linting. Then `./scripts/check.sh` must run so `scripts/check-project.sh` enforces formatter check mode and linting through the same deterministic gate used by hooks and CI.

The agent should paste the failing output back into its reasoning and fix the actual cause. It should not guess from memory when deterministic output is available.

#### Explicit Continuous Step Review (only when requested)

Use a sub-agent for this review only when the user explicitly asks for sub-agents. Otherwise, do the blocker-only review locally after narrow checks.

Sub-agent: **Step Reviewer** (code review after each implementation step).

Prompt:

```text
Review only the current step diff and the narrow check output.
Use the Step 10 review checklist.
Report only blockers and exact fixes.
Do not suggest optional cleanup or style-only edits.
If there are no blockers, reply exactly: approved for next step
```

Speed guidance when sub-agents are explicitly requested:

- Start this review immediately after narrow checks, while broader checks are running.
- Use this on every medium/high-risk step; for low-risk work, run it every second step.

### 7. Close The Loop

Before finishing, update:

- `agent/ubiquitous-language.md` if new domain terms were introduced.
- `agent/design-tree.md` if a design decision moved from open to settled.
- `agent/architecture.md` if a boundary changed.
- `agent/adr/` if the change affects future implementation choices.

#### Explicit Final Independent Review (only when requested)

Use a sub-agent for this review only when the user explicitly asks for one. Otherwise, perform the final blocker check locally.

Sub-agent: **Final Reviewer** (independent merge gate).

Prompt:

```text
Review the full diff before merge using the Step 10 checklist.
Prioritize boundary integrity, test safety, adapter isolation, and stale instruction files.
Report only merge blockers and exact fixes.
If there are no blockers, reply exactly: approved for merge
```

## Step 8.5: Use Worktrees For Parallel Agent Implementations

Git worktrees let one repository have multiple checked-out working directories that share the same Git object store. For agentic coding, this is useful when one prompt could produce several plausible implementations. Instead of asking one agent to explore everything in one branch, create separate worktrees, send each agent into a different branch, run the same checks, then choose the best implementation from real diffs and tool output.

Use worktrees when:

- A feature has two or three viable designs.
- A bug fix is ambiguous and the cheapest way to learn is to try competing fixes.
- A refactor touches an entropy hotspot.
- `improving-architecture` could produce multiple boundary shapes.
- A medium/high-risk slice would benefit from an independent implementation attempt before review.

Do not use worktrees for tiny edits where setup and review cost more than the change.

### 1. Prepare The Base

Start from a clean main worktree. Do not create variants from a dirty directory.

```bash
git fetch origin
git status --short
git rev-parse --abbrev-ref HEAD
```

Pick one base commit or branch, usually `origin/main`:

```bash
BASE=origin/main
REPO="$(basename "$(pwd)")"
WT_ROOT="../${REPO}.worktrees"
```

Create a sibling directory for worktrees, outside the repository directory:

```bash
mkdir -p "$WT_ROOT"
```

Keeping worktrees beside the repo avoids nested repositories, accidental editor search noise, and accidental commits of worktree files.

### 2. Create One Branch Per Attempt

Use a branch naming pattern that makes purpose and variant obvious:

```text
agents/<task-slug>-a
agents/<task-slug>-b
agents/<task-slug>-c
```

Create the branches and worktrees:

```bash
git worktree add -b agents/<task-slug>-a "$WT_ROOT/<task-slug>-a" "$BASE"
git worktree add -b agents/<task-slug>-b "$WT_ROOT/<task-slug>-b" "$BASE"
git worktree add -b agents/<task-slug>-c "$WT_ROOT/<task-slug>-c" "$BASE"
```

For an existing remote branch:

```bash
git fetch origin
git worktree add --track -b <branch-name> "$WT_ROOT/<branch-name>" origin/<branch-name>
```

Useful defaults:

```bash
git config --global worktree.guessRemote true
git config --global checkout.defaultRemote origin
```

Git will refuse to check out the same branch in two worktrees at the same time. Treat that refusal as a useful safety rail: every competing agent attempt should have its own branch.

### 3. Hydrate Each Worktree

Each worktree has its own working files. Ignored local files, installed dependencies, virtual environments, build output, and `.env` files are not automatically copied.

For each worktree:

```bash
cd "$WT_ROOT/<task-slug>-a"
./agent/scripts/agent-doctor.sh
./scripts/check.sh
```

Then run the project setup command for that stack, such as `npm install`, `pnpm install`, `uv sync`, `pip install -r requirements.txt`, or `go mod download`.

If local environment files are needed, copy only non-production local files and never commit them:

```bash
cp /path/to/main-worktree/.env.local .env.local
```

### 4. Give Agents Bounded Prompts

Every branch gets the same feature brief and the same definition of done, but a different implementation angle.

Example prompt for variant A:

```text
You are working in ../<repo>.worktrees/<task-slug>-a on branch agents/<task-slug>-a.

Implement one safe internal step for:
[feature brief]

Bias this attempt toward the simplest implementation that preserves the existing public interfaces.

Read canonical files under agent/ as needed.
Do not touch other worktrees.
Run the formatter command after code edits, then narrow checks, then ./scripts/check.sh.
Final response must include changed files, checks run, checks skipped, tests changed, manifest changed, and agent/ docs updated.
```

Example variants:

- Variant A: smallest implementation.
- Variant B: strongest type/interface boundary.
- Variant C: architecture cleanup first, but only if protected by tests.

This gives the chooser meaningful alternatives instead of three copies of the same solution.

### 5. Compare Using Evidence

After each branch has run checks, collect comparable evidence:

```bash
git -C "$WT_ROOT/<task-slug>-a" status --short
git -C "$WT_ROOT/<task-slug>-a" diff --stat "$BASE"...HEAD
git -C "$WT_ROOT/<task-slug>-a" diff "$BASE"...HEAD
```

Ask the model to choose using this decision rule:

```text
Compare variants A, B, and C against the feature brief.

Choose the winner using:
1. Correct behavior and passing checks.
2. Smallest coherent public interface.
3. Least boundary drift.
4. Tests that protect behavior without weakening existing tests.
5. Lowest future context cost for the next agent.

Return:
- winner
- why rejected each other variant
- exact commits or files to keep
- follow-up cleanup, if any
```

Do not choose the largest diff merely because it appears more complete. Prefer the implementation that makes the next change easier.

### 6. Integrate The Winner

The lowest-friction path is usually to push the winning branch and open a pull request:

```bash
git -C "$WT_ROOT/<task-slug>-a" push -u origin agents/<task-slug>-a
```

If you need a separate integration branch:

```bash
git switch -c integrate/<task-slug> origin/main
git merge --no-ff agents/<task-slug>-a
./scripts/check.sh
```

When combining selected commits from multiple variants, cherry-pick deliberately and rerun the full gate:

```bash
git cherry-pick <commit-sha>
./scripts/check.sh
```

If the winning branch changed tests intentionally, run:

```bash
./scripts/update-test-manifest.sh
./scripts/check.sh
```

### 7. Clean Up

Remove worktrees with Git, not by deleting directories manually:

```bash
git worktree list
git worktree remove "$WT_ROOT/<task-slug>-b"
git worktree remove "$WT_ROOT/<task-slug>-c"
git worktree prune
```

Delete losing local branches only after confirming no useful work remains:

```bash
git branch -D agents/<task-slug>-b
git branch -D agents/<task-slug>-c
```

If losing branches were pushed:

```bash
git push origin --delete agents/<task-slug>-b
git push origin --delete agents/<task-slug>-c
```

For merged GitHub pull request branches, delete the head branch after merge unless another open pull request uses it as its base.

### Repository Steps That Benefit Most

The strongest worktree candidates in this workflow are:

- **First Agent Prompt For A New Project**: when the user explicitly asks for parallel agent work, run two or three complete implementation plans before choosing the project foundation.
- **Per-Feature Developer Workflow**: when explicitly requested, use worktrees on medium/high-risk features, not every small change.
- **Sub-Agent Review Overlay**: only when explicitly requested, give reviewers real competing diffs instead of only one implementation to critique.
- **Weekly Maintenance**: when explicitly requested, try two refactor steps for the same entropy hotspot and keep the one that reduces future context needs.
- **Architecture Reviewer escalation**: only when explicitly requested, create separate branches for competing boundary designs, then record the chosen boundary in `agent/architecture.md` or an ADR.

Worktrees add speed only when the comparison is disciplined. Every variant must start from the same base, receive the same acceptance criteria, run the same checks, and be cleaned up after the decision.

References:

- [Git worktree documentation](https://git-scm.com/docs/git-worktree.html)
- [GitHub branches and pull requests documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-branches)

## Step 9: Use ADRs For Decisions That Future Agents Must Remember

Create ADRs only for decisions that will matter later. Do not write an ADR for every tiny implementation detail.

Template:

```md
# ADR N: [Decision Name]

## Status

Accepted

## Context

[What forced this decision?]

## Decision

[What did we choose?]

## Consequences

- [Benefit]
- [Tradeoff]
- [Follow-up]
```

Good ADR triggers:

- Choosing a bounded context boundary.
- Choosing where domain logic lives.
- Introducing a new adapter.
- Changing persistence shape.
- Changing test strategy.
- Adding a cross-cutting abstraction.

## Step 10: Review Agents Like Junior Engineers With Perfect Typing Speed

Agent output should be reviewed for design drift, not just syntax.

Review checklist:

- Does the code use the ubiquitous language?
- Did it change only the intended bounded context?
- Are public interfaces smaller than implementations?
- Are external systems behind adapters?
- Are tests checking behavior rather than implementation trivia?
- Did it add new generic helpers without enough evidence?
- Did it weaken or delete tests?
- Did it leave instruction files stale?
- Did it increase coupling by importing internals from another module?

The most important review question is: "Will the next agent need less context or more context because of this change?"

## Practical Rollout Plan

Do this in order. Each phase should leave behind a repo-owned artifact, a deterministic command, or both. The point is to turn agent behavior into a repeatable engineering system instead of a collection of good prompts.

### Day 0: Bootstrap

Goal: create the control plane before asking agents to build features.

1. Create `agent/` with the canonical files listed in Step 1. Keep each file short enough that an agent can load it at the start of work.
2. Fill `agent/project-brief.md` with the product goal, primary workflows, non-goals, external systems, and definition of done. Do not start implementation until the primary workflows are named.
3. Create `agent/ubiquitous-language.md` as a table of `Business Term | Technical Symbol | Definition | Constraints`. Pull the first terms from `Plan.md`: design concept, design tree, bounded context, ubiquitous language, feedback loop, entropy hotspot, vertical slice, adapter, seam, and ADR.
4. Create `agent/design-tree.md` with three sections: `Open Decisions`, `Settled Decisions`, and `Pressure Points`. The first version can be rough, but it must name the choices that are still uncertain.
5. Run the `grill-me` pre-flight review from `Plan.md` before creating architecture rules. In this repo, implement that as the `grill-me` skill or a `grill-me` alias that loads `agent/skills/grill-me/SKILL.md`.
6. During `grill-me`, make the agent critique the proposed design for reliability, context management, security, and scalability. Require short answers to: "What is unclear?", "What will agents likely misunderstand?", "What test proves the first behavior?", and "What decision must be recorded now?"
7. Update `agent/design-tree.md` and `agent/ubiquitous-language.md` based on the grilling output. The review is not complete until the repo files change or the agent states that no change is needed and why.
8. Add `agent-rules.md`, `task-routing.md`, `tool-instruction-template.md`, `architecture.md`, and `testing-policy.md`. These files should tell agents how to route the task, what to read, which bounded context they may touch, when tests may change, and which checks must run.
9. Add the task workflow skills: `planning`, `adding-features`, `debugging`, and `explaining-codebase`.
10. Add the supporting skills: `grill-me`, `interview-me`, `testing-vertical-slices`, `improving-architecture`, and `tracking-entropy`. Each skill should include trigger conditions, required inputs, required output, and which repo files it may update.
11. Add `agent-doctor.sh`, `sync-agent-env.sh`, `entropy-hotspots.sh`, `scripts/check.sh`, `scripts/check-md.sh`, `scripts/check-tests-unchanged.sh`, and `scripts/update-test-manifest.sh`.
12. Run `agent/scripts/agent-doctor.sh` and `./scripts/check.sh`. Fix missing files before starting feature work.

### Week 1: Make Feedback Deterministic

Goal: make every agent change pass through the same local checks.

1. Choose the project commands and write them into `agent/testing-policy.md`: `format`, `lint`, `typecheck`, `unit test`, `integration test`, `e2e smoke`, and `check`. If a command does not exist yet, write `not available yet` and the reason.
2. Configure `scripts/check-project.sh` as the project-specific quality gate. Put formatter check mode first, then lint, then typecheck and tests. Do not create a second script for this.
3. Record the mutating formatter command in `agent/testing-policy.md` so agents know what to run immediately after code edits before they run the gate.
4. Make `./scripts/check.sh` the manual one-command gate. It should call Markdown checks, test-manifest checks, and `scripts/check-project.sh`.
5. Add `tests/.manifest.sha256` by running `./scripts/update-test-manifest.sh`. From this point forward, `./scripts/check-tests-unchanged.sh` tells you whether tests changed since the last approved manifest.
6. Define the test-change rule in `agent/testing-policy.md`: existing tests must not be weakened during implementation; intentional test changes require a matching manifest update and a short explanation in the final response.
7. Turn on strict typechecking as far as the current codebase allows. If strict mode creates too much noise, document the relaxed rule and the plan to tighten it.
8. Add import-boundary rules for the highest-value bounded contexts first. Start with one or two forbidden imports that catch real mistakes rather than a large policy that nobody understands.
9. Add one E2E smoke test for the most important workflow. Keep it thin: it should prove the app starts and the primary path works, not exhaustively test every variant.
10. Update `agent/agent-rules.md` so every agent final response includes checks passed, checks skipped, and whether tests were changed.
11. Run the formatter after code edits, then run `./scripts/check.sh` manually before and after feature work. This replaces continuous watching; you decide when you want assurance.

### Week 2: Improve Agent Memory

Goal: move repeated explanations out of chat and into files agents can read.

1. Review the last few feature discussions, bug reports, or design notes. Extract repeated domain terms into `agent/ubiquitous-language.md`.
2. Use `grill-me` whenever a term is ambiguous. The skill should ask whether the term belongs to the business domain, technical implementation, UI copy, or external-system vocabulary.
3. Add ADRs for decisions that repeatedly confuse agents: bounded context ownership, persistence shape, adapter boundaries, test strategy, and naming conventions.
4. Move long prompt paragraphs into `agent/` files. A good rule: if you paste the same instruction twice, it belongs in the repo.
5. Run `agent/scripts/sync-agent-env.sh` so `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`, and `.codex/AGENTS.md` are generated from the same source.
6. Run `agent-doctor.sh` after syncing. It should fail if a canonical file is missing or if a generated shim is stale.
7. Update `agent/skills/*/SKILL.md` when a repeated workflow appears. Keep each skill focused: one trigger, one process, one expected output.

### Week 3: Reduce Entropy

Goal: use agents to make the codebase easier to change, not just larger.

1. Run `agent/scripts/entropy-hotspots.sh` and pick one file or module with high churn. Do not start with the worst file if it is too broad; choose the smallest hotspot that affects current work.
2. Run the `tracking-entropy` skill. Required output: why the file changes often, which concepts are mixed together, what tests currently protect it, and what change would reduce future context needs.
3. Run `improving-architecture` on the chosen hotspot. Ask it to identify shallow modules, hidden domain concepts, unclear ownership, and imports that cross boundaries.
4. Choose one small refactor: extract a domain concept, move adapter code behind an interface, shrink a public API, or merge shallow pass-through modules.
5. Before refactoring, run `testing-vertical-slices` to identify the smallest behavior test that protects the boundary. Add or identify that test before implementation.
6. Make the refactor in one internal implementation step. Avoid broad cleanup unless it directly supports the new boundary.
7. Run targeted tests first, then `./scripts/check.sh`.
8. Record the decision in an ADR if future agents need to preserve the boundary. Update `agent/architecture.md` if imports or ownership changed.

### Ongoing: Per Feature

Goal: make every feature follow the same generate-check-fix loop.

1. Write a feature brief with `Feature`, `Domain Language`, `Bounded Context`, `Expected Behavior`, and `Checks`.
2. If no approved plan exists, run `planning`, present the plan, and stop until the user ratifies it.
3. Load the relevant canonical files: `project-brief.md`, `design-tree.md`, `architecture.md`, `ubiquitous-language.md`, `testing-policy.md`, and `agent-rules.md`.
4. Run `grill-me` for non-trivial work, ambiguous bug fixes, architecture changes, cross-context changes, or security-sensitive changes. Use `interview-me` only if `grill-me` leaves unresolved user judgment.
5. Run `testing-vertical-slices` before implementation. It should choose the narrowest useful test level: unit for pure rules, integration for adapters or persistence, E2E smoke for user workflows, and property-based tests for invariants.
6. Define types, interfaces, and public boundaries first. Use names from `agent/ubiquitous-language.md`; add new terms before using them widely.
7. Write or identify the smallest useful test. If the test suite must change, run `./scripts/update-test-manifest.sh` after the intentional edit and explain why the manifest changed.
8. Implement one ratified internal feature slice. Keep external systems behind adapters and avoid importing another bounded context's internals.
9. Run the mutating formatter command recorded in `agent/testing-policy.md`, then the narrowest check first, then broader checks, then `./scripts/check.sh`.
10. If checks fail, repair from actual tool output. Do not weaken tests unless the feature brief explicitly says the expected behavior changed.
11. Close the loop by updating `ubiquitous-language.md`, `design-tree.md`, `architecture.md`, or an ADR when the change creates durable knowledge.
12. Final response must state: what changed, which skill was used, which checks ran, whether tests changed, whether the manifest changed, and whether temporary session state was cleared.

Sub-agent cadence:

- Use sub-agents only when the user explicitly asks for them.
- Keep requested reviewer outputs focused on blockers only.
- Without explicit sub-agent approval, perform the same review locally in the main agent.

## What To Avoid

- Do not let agents implement across the whole repo from a vague prompt.
- Do not store important instructions only in chat.
- Do not give write access to production systems through MCP.
- Do not let agents weaken tests during implementation.
- Do not create generic `utils`, `helpers`, `managers`, or `services` without a domain name.
- Do not split modules by framework layer when the domain boundary is clearer.
- Do not add heavyweight process for every small change. Use stronger ceremony only when the change affects architecture, security, data, or critical workflows.

## The Practical Standard

A codebase is agent-ready when a new agent can answer these questions from repo files and tools, without relying on hidden conversation history:

1. What is this app trying to do?
2. What domain words should I use?
3. Which bounded context am I changing?
4. What public interface should I respect?
5. Which tests prove the behavior?
6. Which commands tell me I broke something?
7. Where do I record a design decision?

If those answers are easy to find, agents will produce smaller, safer, more coherent changes. If those answers are missing, agents will compensate by inventing structure, and that is where entropy accelerates.
