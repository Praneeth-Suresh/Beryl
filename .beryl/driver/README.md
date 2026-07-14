# Agent Driver

A long-running orchestrator that drives the codebase through a series of large
changes, one task at a time, using **separate headless agent sessions** for
each phase so every step runs with a fresh, full context window.

## Choosing the coding agent

The driver is agent-agnostic. `DRIVER_AGENT` in `config.env` selects which
coding agent runs each phase session:

- `codex` — OpenAI Codex CLI (`codex exec`)
- `claude` — Claude Code CLI (`claude -p`)
- `gemini` — Gemini CLI (`gemini -p`)
- `custom` — any headless command via `CUSTOM_AGENT_CMD` (the phase prompt is
  appended as the final argument; the command must print its transcript to
  stdout and exit non-zero on failure)

If `DRIVER_AGENT` is unset and the driver runs on an interactive terminal, it
presents this list, lets you pick, and saves the choice to `config.env`.
Non-interactive runs fail fast with instructions instead of guessing.

## The cycle

For each task, the driver runs phases as independent headless agent
sessions:

```
        ┌─────────────────────────────────────────────┐
        │                                             │
   PLAN ──▶ IMPLEMENT ──▶ VERIFY (codebase checks / runtime evidence)
        │                       │
        │             PASS ─────┴───▶ COMMIT (no push) ──▶ next task
        │             FAIL
        └──────◀── replan (attempt += 1, up to MAX_ATTEMPTS)
```

- **PLAN** — reads the task brief + `.beryl/agent/task-routing.md` planning workflow,
  writes a plan into the task's session-state file. No code edits.
- **IMPLEMENT** — implements strictly against the ratified plan.
- **VERIFY** — independently checks the result **against the original task
  brief** (not against the implementer's own claims). For docs, scripts,
  config, and other codebase-only work, verification uses repository inspection
  and deterministic checks. For runtime/browser/API work, verification uses the
  task's declared runtime evidence. Emits a machine-readable `VERIFY: PASS` or
  `VERIFY: FAIL` sentinel plus a reason.
- On **FAIL** → loops back to PLAN with the failure reason folded in
  (`attempt += 1`), up to `MAX_ATTEMPTS`, then blocks and stops.
- If a required runtime verification stack cannot start cleanly, the driver
  writes `VERIFY: FAIL` with `KIND: verify_stack_failure`, blocks immediately,
  and does **not** consume a task attempt. This keeps stale ports/processes from
  being mistaken for app behavior.
- On **PASS** → **COMMIT** phase commits the change (never pushes).
- After a successful **COMMIT**, if the task brief has a `beryl-github-issue`
  marker, the driver comments on the issue with the commit, verification
  evidence, and confidence level, then attempts to close it. This GitHub
  finalization is soft-only: failures are recorded in task state but do not
  fail the local commit.

Each phase is a *separate process invocation*, which is exactly why context stays
accurate: no single session accumulates the whole multi-task history.

## How context is captured accurately

The driver does **not** rely on the model's chat memory between phases. Instead
every phase reads/writes durable files on disk, and each prompt is rebuilt from
scratch from those files:

| File                                    | Role                                                                | Lifetime   |
| --------------------------------------- | ------------------------------------------------------------------- | ---------- |
| `tasks/NN-*.md`                       | Immutable task brief (the source of truth a phase verifies against) | committed  |
| `prompts/*.md`                        | Phase prompt templates with`{{PLACEHOLDERS}}`                     | committed  |
| `state/NN/session-state.md`           | Per-task working state: plan, slices, failures, attempt no.         | gitignored |
| `state/NN/plan.md`                    | Latest ratified plan                                                | gitignored |
| `state/NN/verify.txt`                 | Latest verify sentinel + reason                                     | gitignored |
| `state/NN/issue-comment.md`           | GitHub issue completion comment body, when a task is linked         | gitignored |
| `state/NN/issue-finalize.txt`         | Soft GitHub comment/close result for linked issue tasks             | gitignored |
| `state/optimization/`                 | Optional task DAG, verification report, waves, and worktree records | gitignored |
| `state/NN/status`                     | One of `pending                                                     | planning   |
| `logs/<run-id>/NN-PHASE-attemptK.log` | Full stdout/stderr of each session                                  | gitignored |

Because state lives in files, a phase that crashes or a machine that reboots can
be resumed: re-running `run.sh` skips tasks already `committed` and resumes the
current task from its `status`.

If a task already has a non-empty `state/NN/plan.md` and no failed verification
context, the driver reuses that plan on resume and continues at IMPLEMENT
instead of spending another session re-planning the same task.

The orchestration logic (loop / branch / gate) lives in **bash**, not in the
model — so the control flow is deterministic and inspectable, and the model is
only ever asked to do one bounded phase at a time.

## Layout

```
.beryl/driver/
├── run.sh                 # the orchestrator (state machine)
├── import-github-issues.sh # imports GitHub issues as task briefs
├── optimize-worktrees.sh   # optional DAG/worktree optimization preflight
├── lib/common.sh          # helpers: prompt compose, sentinel parse, git, stack
├── lib/import_github_issues.py
├── lib/worktree_optimizer.py
├── config.example.env     # copy to config.env and edit
├── prompts/
│   ├── plan.md
│   ├── implement.md
│   ├── verify.md
│   ├── commit.md
│   └── optimize.md
├── tasks/                 # one brief per task, run in listed order
│   ├── 01-align-score-breakdown-with-network-graph.md
│   └── 02-analysis-card-clickable-navigation.md
├── state/                 # gitignored runtime state
├── logs/                  # gitignored session logs
└── README.md
```

## Prerequisites

- GitHub CLI on PATH (`gh`) when importing issues from GitHub.
- GitHub CLI on PATH (`gh`) and authenticated when finalizing linked GitHub
  issues after completed tasks. Missing or failed GitHub finalization is
  recorded softly and does not fail the local task commit.
- The selected coding agent CLI on PATH (`codex`, `claude`, `gemini`, or your
  `CUSTOM_AGENT_CMD` binary).
- Runtime/browser dependencies only when the task or project check policy
  requires runtime verification.
- A clean-ish git working tree on the base branch.

## Setup

```bash
cd .beryl/driver
cp config.example.env config.env
# edit config.env: set DRIVER_AGENT (or leave empty to choose interactively),
# per-agent model/flags if desired, confirm branch and verification mode
```

## Import GitHub issues

The driver can populate task briefs from the GitHub repository where Beryl is
installed:

```bash
# from repo root
bash .beryl/driver/import-github-issues.sh
```

By default, the importer uses `gh repo view` or the Git `origin` remote to find
the repository, fetches open issues with `gh issue list`, and creates numbered
task briefs under `.beryl/driver/tasks/`. Each generated brief includes a stable
`beryl-github-issue` marker so re-running the importer skips issues that were
already copied.

The same marker is used after a task commit succeeds. The driver writes a
completion comment to the linked issue describing the committed task, the
verification evidence, and a confidence level, then tries to close the issue.
The comment/close step uses the GitHub CLI and is soft-only. If `gh` is missing,
unauthenticated, offline, or GitHub rejects the operation, the driver records
the failure in `.beryl/driver/state/NN/issue-finalize.txt` and still marks the
locally committed task complete. Set `GITHUB_ISSUE_FINALIZE=false` in
`.beryl/driver/config.env` to skip this remote finalization during offline runs.

After writing tasks, the importer prompts you to verify that every GitHub issue
was copied correctly before continuing. Use `--complete-all` for non-interactive
or already-reviewed imports:

```bash
bash .beryl/driver/import-github-issues.sh --complete-all
```

Useful options:

```bash
bash .beryl/driver/import-github-issues.sh --repo OWNER/REPO
bash .beryl/driver/import-github-issues.sh --state all
bash .beryl/driver/import-github-issues.sh --limit 200
bash .beryl/driver/import-github-issues.sh --clear-stale-state
bash .beryl/driver/import-github-issues.sh --dry-run
```

Task allocation is conservative:

- If the driver still has only placeholder task files, imported issues replace
  the first placeholder slots, leaving unused placeholders in place.
- If real task files or unfinished driver state already exist, imported issues
  are allocated after that work so an in-progress run is not reordered.
- Orphaned state directories are treated as stale runtime material. By default
  they are preserved and their ids are not reused; pass `--clear-stale-state` to
  remove only state directories that no longer have a matching task file.
- If GitHub has no matching issues, the importer exits successfully without
  creating task files.

## Run

```bash
# from repo root
bash .beryl/driver/run.sh                 # run all tasks in order
bash .beryl/driver/run.sh --task 03       # run a single task by number
bash .beryl/driver/run.sh --from 02       # run task 02 onward
bash .beryl/driver/run.sh --status        # print per-task status and exit
bash .beryl/driver/run.sh --resume        # continue where a previous run stopped
bash .beryl/driver/run.sh --optimize-worktrees     # prepare parallel worktrees first
bash .beryl/driver/run.sh --no-optimize-worktrees  # override config and skip optimization
bash .beryl/driver/run.sh --flush-on-complete      # force full-success cleanup
bash .beryl/driver/run.sh --no-flush-on-complete   # preserve state/logs this run
```

The driver creates/uses `WORK_BRANCH` (default `feat/agent-driver-build`) off
`BASE_BRANCH`. It commits after each task passes verification. **It never pushes.**
When all tasks are `committed`, push manually after your own review:

```bash
git push -u origin feat/agent-driver-build   # only when YOU are ready
```

## Optional worktree optimization

Set `DRIVER_OPTIMIZE_WORKTREES=true` in `.beryl/driver/config.env`, or pass
`--optimize-worktrees`, to run a preflight before any selected task starts.
The preflight:

- collects the selected task briefs using the same run scope as `run.sh`
  (`all`, `--task NN`, or `--from NN`);
- asks the configured agent for a task DAG through `prompts/optimize.md`;
- verifies the DAG deterministically with `lib/worktree_optimizer.py`;
- computes topological waves; and
- prepares per-task Git worktrees below `DRIVER_WORKTREE_ROOT` only when a
  verified wave contains more than one ready task.

Optimization state is written under `.beryl/driver/state/optimization/`:

| File | Meaning |
| --- | --- |
| `tasks.json` | Selected task ids, titles, and paths. |
| `dag.raw.json` | Agent-proposed DAG after JSON extraction. |
| `dag.verified.json` | Deterministically verified DAG, dependencies, waves, and `parallelizable`. |
| `waves.txt` | Human-readable topological waves. |
| `worktrees.txt` | Created task worktree branch/path records, or a no-parallel-wave note. |
| `status` | `OPTIMIZE_WORKTREES: PASS` or `OPTIMIZE_WORKTREES: FAIL` with detail. |

If DAG verification or worktree creation fails, the driver blocks before
implementation begins. Existing behavior is unchanged when optimization is not
enabled.

This first slice prepares worktrees for parallel development. It does not yet
auto-run worker drivers in those worktrees, auto-merge task branches, or change
the main task loop: `run.sh` still executes selected tasks sequentially on
`WORK_BRANCH`.

## Runtime state and log retention

After an unscoped full run completes successfully, the driver clears accumulated
runtime material under `.beryl/driver/state/` and `.beryl/driver/logs/`. The
parent directories remain in place, and any git-tracked placeholder files below
those roots, such as a future `.gitkeep`, are preserved.

The flush is intentionally narrow:

- It runs only after the task loop reaches the successful all-committed path.
- Failed, blocked, or interrupted runs preserve state and logs for inspection.
- Scoped runs using `--task` or `--from` preserve state and logs outside the
  selected scope.
- `--resume` without `--task` or `--from` is still a full-run completion
  candidate.
- `--status` and `--selftest` never flush runtime material.

`FLUSH_ON_COMPLETE` controls the default behavior. Accepted values are
`true/false`, `yes/no`, `on/off`, or `1/0`. Precedence is:

1. `--flush-on-complete` or `--no-flush-on-complete` for the current invocation.
2. `FLUSH_ON_COMPLETE` from `.beryl/driver/config.env`.
3. The default from `.beryl/driver/config.example.env` when `config.env` is
   absent.

## Testing the driver without burning agent sessions

`DRIVER_MOCK=1` swaps the real Codex sessions and dev-stack calls for a deterministic
fake responder, so you can prove the state machine (fail→replan→pass→commit,
max-attempts blocking, resume-skip) end to end without any model calls:

```bash
DRIVER_MOCK=1 bash .beryl/driver/run.sh --selftest
DRIVER_MOCK=1 DRIVER_OPTIMIZE_WORKTREES=true bash .beryl/driver/run.sh --selftest
```

See `lib/common.sh` `mock_*` functions for the scripted behaviors.

The worktree optimizer has a deterministic selftest for valid independent and
serial DAGs, unknown nodes, cycles, duplicate dependencies, self-dependencies,
and single-task no-op selection:

```bash
bash .beryl/driver/optimize-worktrees.sh --selftest
```

The issue importer also has a network-free selftest for placeholder replacement,
duplicate imports, unfinished state, stale state, and empty issue lists:

```bash
bash .beryl/driver/import-github-issues.sh --selftest
```

## Safety notes

- Headless sessions default to `--sandbox workspace-write` and
  `-c approval_policy="never"` through `CODEX_SANDBOX`/`CODEX_APPROVAL`, but
  the driver refuses to start in that unattended mode until you set
  `DRIVER_UNATTENDED_OK="true"` in your local `config.env`. Review
  `WORK_BRANCH` diffs before pushing.
- Task briefs (`tasks/*.md`), prompt templates (`prompts/*.md`), and
  `config.env` are **trusted inputs**: anyone who can edit them steers an
  unattended agent. Keep them under the same review bar as code, and prefer
  running the driver inside a container/VM boundary.
- `CODEX_EXTRA_ARGS` accepts only simple whitespace-separated tokens; quoting
  and shell metacharacters are rejected rather than word-split.
- `VERIFY_STACK_MODE` controls optional runtime stack startup:
  - `auto` starts the bundled legacy backend/frontend verifier only when the
    repository has that layout.
  - `always` requires that legacy verifier and blocks if it cannot start.
  - `never` skips stack startup; verification must use repository checks and
    task-specific evidence.
- When the legacy verifier is started, it uses an **isolated** stack and a
  **copy** of the dev SQLite DB, so it never mutates canonical dev data. The
  stack allocates fresh free ports per run (`VERIFY_FRONTEND_PORT=auto`,
  `VERIFY_BACKEND_PORT=auto`) unless fixed ports are configured.
- The verify stack binds to loopback (`VERIFY_BIND_HOST=127.0.0.1`) so the
  dev-mode backend and its data copy are never reachable from other hosts.
  Override only when you need cross-host access and understand the exposure.
- Rate-limit retries use linear backoff from `RATE_LIMIT_COOLDOWN` and are only
  triggered after a failed Codex process reports a rate-limit style error.
- The driver commits but never pushes, and never force-operates on git.
