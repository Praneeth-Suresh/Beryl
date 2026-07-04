# Agent Driver

A long-running orchestrator that drives the codebase through a series of large
changes, one task at a time, using **separate headless `codex exec` sessions** for
each phase so every step runs with a fresh, full context window.

## The cycle

For each task, the driver runs phases as independent `codex exec`
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

Each phase is a *separate process invocation*, which is exactly why context stays
accurate: no single session accumulates the whole multi-task history.

## How context is captured accurately

The driver does **not** rely on the model's chat memory between phases. Instead
every phase reads/writes durable files on disk, and each prompt is rebuilt from
scratch from those files:

| File | Role | Lifetime |
| --- | --- | --- |
| `tasks/NN-*.md` | Immutable task brief (the source of truth a phase verifies against) | committed |
| `prompts/*.md` | Phase prompt templates with `{{PLACEHOLDERS}}` | committed |
| `state/NN/session-state.md` | Per-task working state: plan, slices, failures, attempt no. | gitignored |
| `state/NN/plan.md` | Latest ratified plan | gitignored |
| `state/NN/verify.txt` | Latest verify sentinel + reason | gitignored |
| `state/NN/status` | One of `pending|planning|implementing|verifying|passed|committed|blocked` | gitignored |
| `logs/<run-id>/NN-PHASE-attemptK.log` | Full stdout/stderr of each session | gitignored |

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
├── lib/common.sh          # helpers: prompt compose, sentinel parse, git, stack
├── config.example.env     # copy to config.env and edit
├── prompts/
│   ├── plan.md
│   ├── implement.md
│   ├── verify.md
│   └── commit.md
├── tasks/                 # one brief per task, run in listed order
│   ├── 01-align-score-breakdown-with-network-graph.md
│   └── 02-analysis-card-clickable-navigation.md
├── state/                 # gitignored runtime state
├── logs/                  # gitignored session logs
└── README.md
```

## Prerequisites

- Codex CLI on PATH (`codex exec`).
- Runtime/browser dependencies only when the task or project check policy
  requires runtime verification.
- A clean-ish git working tree on the base branch.

## Setup

```bash
cd .beryl/driver
cp config.example.env config.env
# edit config.env: set CODEX_MODEL/CODEX_PROFILE if desired, confirm branch and verification mode
```

## Run

```bash
# from repo root
bash .beryl/driver/run.sh                 # run all tasks in order
bash .beryl/driver/run.sh --task 03       # run a single task by number
bash .beryl/driver/run.sh --from 02       # run task 02 onward
bash .beryl/driver/run.sh --status        # print per-task status and exit
bash .beryl/driver/run.sh --resume        # continue where a previous run stopped
```

The driver creates/uses `WORK_BRANCH` (default `feat/agent-driver-build`) off
`BASE_BRANCH`. It commits after each task passes verification. **It never pushes.**
When all tasks are `committed`, push manually after your own review:

```bash
git push -u origin feat/agent-driver-build   # only when YOU are ready
```

## Testing the driver without burning agent sessions

`DRIVER_MOCK=1` swaps the real Codex sessions and dev-stack calls for a deterministic
fake responder, so you can prove the state machine (fail→replan→pass→commit,
max-attempts blocking, resume-skip) end to end without any model calls:

```bash
DRIVER_MOCK=1 bash .beryl/driver/run.sh --selftest
```

See `lib/common.sh` `mock_*` functions for the scripted behaviors.

## Safety notes

- Headless sessions default to `--sandbox workspace-write` and
  `-c approval_policy="never"` through `CODEX_SANDBOX`/`CODEX_APPROVAL`.
  Review `WORK_BRANCH` diffs before pushing.
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
- Rate-limit retries use linear backoff from `RATE_LIMIT_COOLDOWN` and are only
  triggered after a failed Codex process reports a rate-limit style error.
- The driver commits but never pushes, and never force-operates on git.
