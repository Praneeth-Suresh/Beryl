
# Task 06 - Flush driver state and logs when all tasks complete

## Goal

Make the driver automatically clear its runtime `state/` and `logs/` material after a full run
finishes successfully, so the next set of tasks starts from a clean slate without the user manually
deleting files.

## Context

`run.sh` `main()` iterates the selected task briefs and runs each through the plan/implement/verify/
commit phases. Per-task runtime state accumulates under `.beryl/driver/state/<id>/` (`status`, `attempt`,
`plan.md`, `session-state.md`, `verify-shots/`) and per-run logs accumulate under
`.beryl/driver/logs/<RUN_ID>/`. Today these persist after a run completes, so stale state and logs carry
into the next run and the user has to clear them by hand.

The current success path is the end of the `main()` loop, immediately after the loop finishes
without an early failure exit and before/around the final `log "all selected tasks committed ..."`
and `print_status` calls. The early-exit failure branch (`rc -ne 0`) intentionally preserves state
and logs for debugging and must keep doing so. Path helpers `state_root()` and `logs_root()` in
`lib/common.sh` already resolve the two directories to flush.

## Requirements

1. Add a flush step that runs only when a full run completes successfully — that is, the task loop
   in `main()` finishes with every selected task committed and no early failure exit occurred.
2. On flush, clear the accumulated contents of `state/` (per-task directories) and `logs/` (run
   directories) while preserving the `state/` and `logs/` parent directories themselves and any
   tracked placeholder files (for example `.gitkeep`) so the driver still runs afterward.
3. Never flush when the run stops early because a task failed or was blocked; preserve all state and
   logs in that case so the failure can be inspected.
4. Only flush on a full run. When the run is scoped to a subset via a single-task or from-task
   filter, do not wipe state or logs for tasks outside that selection.
5. Make the behavior configurable: add a config toggle in `config.env` / `config.example.env`
   (for example `FLUSH_ON_COMPLETE`) with a safe default, and a matching command-line flag to
   force-enable or disable the flush for a single run. Document the precedence between them.
6. Emit a clear driver log line when the flush runs and when it is skipped, stating what was cleared
   or why it was preserved.
7. Do not flush in `status` or `selftest` modes.

## Acceptance checks

1. After a full successful run, `state/` and `logs/` contain no leftover per-task or per-run
   material, but both directories (and any placeholder files) still exist.
2. After a run that stops on a failed or blocked task, all state and logs from that run remain in
   place and are not cleared.
3. A scoped run using a single-task or from-task filter does not clear state or logs for tasks
   outside the selected scope.
4. Toggling the config option off (or passing the disable flag) leaves state and logs intact even on
   a fully successful run; toggling it on restores the flush.
5. `run.sh status` and `run.sh selftest` complete without triggering any flush.
6. The driver `status` command runs without errors after a flushed run.
7. Markdown and repository sanity checks pass.

## Out of scope

- Changing the driver state machine, phase order, or attempt/retry logic.
- Archiving, compressing, or uploading logs to any external location.
- Altering task-selection semantics beyond honoring existing single-task / from-task filters.
- Pushing commits or changing branch behavior.
