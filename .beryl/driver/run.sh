#!/usr/bin/env bash
# run.sh — agent driver orchestrator.
# Cycle per task: PLAN -> IMPLEMENT -> VERIFY -> (FAIL? replan : COMMIT) .
# Runs each phase as a separate headless Codex session. Commits, never pushes.
#
# Usage:
#   bash .beryl/driver/run.sh                 # all tasks in order
#   bash .beryl/driver/run.sh --task 03       # one task
#   bash .beryl/driver/run.sh --from 02       # from task 02 onward
#   bash .beryl/driver/run.sh --resume        # skip committed, resume current
#   bash .beryl/driver/run.sh --status        # print status table and exit
#   bash .beryl/driver/run.sh --selftest      # control-flow self-test (use with DRIVER_MOCK=1)
set -u

DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DRIVER_DIR

# ── Load config ──────────────────────────────────────────────────────────--
if [ -f "$DRIVER_DIR/config.env" ]; then
  # shellcheck disable=SC1090
  . "$DRIVER_DIR/config.env"
else
  # shellcheck disable=SC1090
  . "$DRIVER_DIR/config.example.env"
fi
VERIFY_FRONTEND_PORT_SETTING="$VERIFY_FRONTEND_PORT"
VERIFY_BACKEND_PORT_SETTING="$VERIFY_BACKEND_PORT"
export REPO_ROOT WORK_BRANCH BASE_BRANCH VERIFY_BASE_URL VERIFY_API_URL \
       VERIFY_FRONTEND_PORT VERIFY_BACKEND_PORT VERIFY_DB SOURCE_DB \
       MAX_ATTEMPTS CODEX_BIN CODEX_MODEL CODEX_PROFILE CODEX_SANDBOX \
       CODEX_APPROVAL CODEX_EXTRA_ARGS DRIVER_MOCK \
       RATE_LIMIT_COOLDOWN MAX_RATE_LIMIT_WAITS VERIFY_STACK_MODE \
       VERIFY_FRONTEND_PORT_SETTING VERIFY_BACKEND_PORT_SETTING

# shellcheck disable=SC1091
. "$DRIVER_DIR/lib/common.sh"

# ── Args ─────────────────────────────────────────────────────────────────--
ONLY_TASK=""; FROM_TASK=""; MODE="run"
while [ $# -gt 0 ]; do
  case "$1" in
    --task) ONLY_TASK="$2"; shift 2 ;;
    --from) FROM_TASK="$2"; shift 2 ;;
    --resume) MODE="resume"; shift ;;
    --status) MODE="status"; shift ;;
    --selftest) MODE="selftest"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_LOG_DIR="$(logs_root)/$RUN_ID"
mkdir -p "$RUN_LOG_DIR"
export RUN_LOG_DIR

cleanup_on_exit() {
  stop_verify_stack
}

trap cleanup_on_exit EXIT
trap 'trap - INT TERM; stop_verify_stack; exit 130' INT TERM

list_tasks() { ls "$(tasks_dir)"/[0-9]*.md 2>/dev/null | sort; }

print_status() {
  printf '\n%-4s %-44s %-12s %s\n' "ID" "TASK" "STATUS" "ATTEMPT"
  printf -- '---------------------------------------------------------------------\n'
  local t id st at
  for t in $(list_tasks); do
    id="$(task_id_from_path "$t")"
    st="$(get_status "$id")"; at="$(get_attempt "$id")"
    if [ "$st" = "blocked" ] && [ "$at" -gt "$MAX_ATTEMPTS" ]; then
      at="${MAX_ATTEMPTS} (max)"
    fi
    printf '%-4s %-44s %-12s %s\n' "$id" "$(basename "$t")" "$st" "$at"
  done
  echo
}

write_verify_stack_failure_state() {
  local id="$1" stack_failure="$2"
  local sd; sd="$(state_dir_for "$id")"
  {
    printf 'VERIFY: FAIL\n'
    if [ -f "$stack_failure" ]; then
      cat "$stack_failure"
    else
      printf 'KIND: verify_stack_failure\n'
      printf 'Verification stack startup failed; no failure detail file was written.\n'
    fi
  } > "$sd/verify.txt"
}

# ── One phase runner: sets global PHASE_LOG; returns agent exit code ───────--
# run_phase TASK_ID PHASE_NAME TEMPLATE
PHASE_LOG=""
run_phase() {
  local id="$1" phase="$2" tmpl="$3"
  local sd; sd="$(state_dir_for "$id")"; mkdir -p "$sd/verify-shots"
  local att; att="$(get_attempt "$id")"
  local logf="$RUN_LOG_DIR/${id}-${phase}-attempt${att}.log"

  # Build placeholder env for compose_prompt.
  export PH_STATE_DIR="$sd"
  export PH_ATTEMPT="$att"
  export PH_TASK_BRIEF; PH_TASK_BRIEF="$(read_file_safe "$TASK_FILE")"
  export PH_PLAN; PH_PLAN="$(read_file_safe "$sd/plan.md")"
  export PH_VERIFY; PH_VERIFY="$(read_file_safe "$sd/verify.txt")"
  export PH_VERIFY_STACK_STATUS="${VERIFY_STACK_STATUS:-not evaluated for this phase}"
  # Failure context only meaningful for re-plan.
  if [ -f "$sd/verify.txt" ] && verify_failed "$sd/verify.txt"; then
    export PH_FAILURE_CONTEXT="Previous verification FAILED with:
$(cat "$sd/verify.txt")
Address every point above in this re-plan."
  else
    export PH_FAILURE_CONTEXT=""
  fi

  local prompt; prompt="$(compose_prompt "$tmpl")"
  log "task $id: $phase (attempt $att) -> $logf"

  local rl_waits=0
  while :; do
    run_agent "$prompt" "$logf"
    local rc=$?

    if [ "$rc" -ne 0 ] && is_rate_limited "$logf"; then
      rl_waits=$((rl_waits + 1))
      if [ $rl_waits -gt "$MAX_RATE_LIMIT_WAITS" ]; then
        warn "task $id: $phase hit rate limit $rl_waits times. Giving up."
        PHASE_LOG="$logf"; return 1
      fi
      local wait_secs=$((RATE_LIMIT_COOLDOWN * rl_waits))
      [ $wait_secs -gt 43200 ] && wait_secs=43200
      local resume_at; resume_at="$(date -d "+${wait_secs} seconds" '+%H:%M %Z %b %d' 2>/dev/null || date '+%H:%M %Z %b %d')"
      warn "task $id: $phase rate-limited. Sleeping ${wait_secs}s (~$(( wait_secs/3600 ))h). Resume ~$resume_at. [$rl_waits/$MAX_RATE_LIMIT_WAITS]"
      sleep "$wait_secs"
      log "task $id: $phase waking from rate-limit cooldown. Retrying..."
      continue
    fi

    [ $rc -ne 0 ] && warn "task $id: $phase session exit code $rc"
    PHASE_LOG="$logf"
    return $rc
  done
}

# ── Drive a single task through the full cycle ────────────────────────────--
run_task() {
  local id="$1"
  TASK_FILE="$(list_tasks | grep -E "/${id}-" | head -n1)"
  [ -z "$TASK_FILE" ] && { warn "no task file for id $id"; return 1; }
  local sd; sd="$(state_dir_for "$id")"; mkdir -p "$sd"

  local st; st="$(get_status "$id")"
  if [ "$st" = "committed" ]; then
    log "task $id already committed — skipping"; return 0
  fi
  [ -f "$sd/attempt" ] || set_attempt "$id" 1
  local reuse_plan=0
  case "$st" in
    planning|implementing|verifying)
      if [ -s "$sd/plan.md" ] && ! verify_failed "$sd/verify.txt"; then
        reuse_plan=1
      fi
      ;;
  esac

  while :; do
    local att; att="$(get_attempt "$id")"
    if [ "$att" -gt "$MAX_ATTEMPTS" ]; then
      set_status "$id" "blocked"
      warn "task $id: exceeded MAX_ATTEMPTS ($MAX_ATTEMPTS) — BLOCKED. Stopping."
      return 2
    fi

    # PLAN
    if [ "$reuse_plan" -eq 1 ]; then
      log "task $id: reusing existing plan.md; resuming at IMPLEMENT"
      reuse_plan=0
    else
      set_status "$id" "planning"
      run_phase "$id" PLAN "$(prompts_dir)/plan.md"; local plan_rc=$? plog="$PHASE_LOG"
      if [ "$plan_rc" -ne 0 ]; then
        set_status "$id" "blocked"
        warn "task $id: PLAN session failed (rc=$plan_rc). Not consuming attempt."
        return 2
      fi
      if phase_blocked_plan "$plog"; then
        set_status "$id" "blocked"
        warn "task $id: PLAN reported BLOCKED. Stopping."
        return 2
      fi
      if ! phase_passed_plan "$plog"; then
        if [ "$att" -ge "$MAX_ATTEMPTS" ]; then
          set_status "$id" "blocked"
          warn "task $id: PLAN produced no READY sentinel on final attempt ($att/$MAX_ATTEMPTS) — BLOCKED. Stopping."
          return 2
        fi
        warn "task $id: PLAN produced no READY sentinel (attempt $att). Bumping attempt."
        set_attempt "$id" "$((att+1))"; continue
      fi
    fi

    # IMPLEMENT
    set_status "$id" "implementing"
    run_phase "$id" IMPLEMENT "$(prompts_dir)/implement.md"; local impl_rc=$? ilog="$PHASE_LOG"
    if [ "$impl_rc" -ne 0 ]; then
      set_status "$id" "blocked"
      warn "task $id: IMPLEMENT session failed (rc=$impl_rc). Not consuming attempt."
      return 2
    fi
    if ! phase_done_implement "$ilog"; then
      warn "task $id: IMPLEMENT not DONE (attempt $att). Re-planning."
      # treat as a soft failure: record and replan
      printf 'VERIFY: FAIL\nImplement phase did not complete: see %s\n' "$ilog" > "$sd/verify.txt"
      if [ "$att" -ge "$MAX_ATTEMPTS" ]; then
        set_status "$id" "blocked"
        warn "task $id: IMPLEMENT incomplete on final attempt ($att/$MAX_ATTEMPTS) — BLOCKED. Stopping."
        return 2
      fi
      set_attempt "$id" "$((att+1))"; continue
    fi

    # VERIFY
    set_status "$id" "verifying"
    local stack_started=0
    if should_start_verify_stack; then
      if ! start_verify_stack; then
        local stack_failure="$RUN_LOG_DIR/verify-stack-failure.txt"
        write_verify_stack_failure_state "$id" "$stack_failure"
        stop_verify_stack
        set_status "$id" "blocked"
        warn "task $id: VERIFY stack failed to start (attempt $att). Infrastructure failure did not consume an attempt."
        return 2
      fi
      stack_started=1
    else
      log "task $id: VERIFY stack skipped (${VERIFY_STACK_STATUS})"
    fi
    run_phase "$id" VERIFY "$(prompts_dir)/verify.md"; local verify_rc=$?
    [ "$stack_started" -eq 1 ] && stop_verify_stack
    if [ "$verify_rc" -ne 0 ]; then
      set_status "$id" "blocked"
      warn "task $id: VERIFY session failed (rc=$verify_rc). Not consuming attempt."
      return 2
    fi

    if verify_passed "$sd/verify.txt"; then
      log "task $id: VERIFY PASSED."
      # COMMIT
      run_phase "$id" COMMIT "$(prompts_dir)/commit.md"; local commit_rc=$? clog="$PHASE_LOG"
      if [ "$commit_rc" -ne 0 ]; then
        set_status "$id" "blocked"
        warn "task $id: COMMIT session failed (rc=$commit_rc). Not consuming attempt."
        return 2
      fi
      if phase_done_commit "$clog"; then
        set_status "$id" "committed"
        log "task $id: committed (no push). Done."
        return 0
      else
        set_status "$id" "blocked"
        warn "task $id: COMMIT phase produced no sentinel. Stopping for review."
        return 2
      fi
    else
      if [ "$att" -ge "$MAX_ATTEMPTS" ]; then
        set_status "$id" "blocked"
        warn "task $id: VERIFY FAILED on final attempt ($att/$MAX_ATTEMPTS) — BLOCKED. Stopping."
        return 2
      fi
      warn "task $id: VERIFY FAILED (attempt $att). Looping back to PLAN."
      set_attempt "$id" "$((att+1))"
      continue
    fi
  done
}

# ── Selftest: exercise control flow in mock mode ──────────────────────────--
selftest() {
  [ "${DRIVER_MOCK:-0}" = "1" ] || die "run --selftest with DRIVER_MOCK=1"
  log "SELFTEST start (mock mode; no real sessions, no git, no servers)"
  local fails=0

  _reset() { rm -rf "$(state_root)/$1"; mkdir -p "$(state_root)/$1"; }
  _expect() { # desc actual expected
    if [ "$2" = "$3" ]; then log "  PASS: $1 ($2)"; else warn "  FAIL: $1 (got '$2' want '$3')"; fails=$((fails+1)); fi
  }

  # Use a real existing task file for brief content.
  local TID="01"
  TASK_FILE="$(list_tasks | grep -E "/${TID}-" | head -n1)"
  local saved_state; saved_state="$(mktemp -d "${TMPDIR:-/tmp}/driver-selftest.XXXXXX")" || return 1
  if [ -d "$(state_root)/$TID" ]; then
    cp -a "$(state_root)/$TID" "$saved_state/$TID"
  fi
  _restore_selftest_state() {
    rm -rf "$(state_root)/$TID"
    if [ -d "$saved_state/$TID" ]; then
      mkdir -p "$(state_root)"
      cp -a "$saved_state/$TID" "$(state_root)/$TID"
    fi
    rm -rf "$saved_state"
  }

  # Scenario A: pass on first verify -> committed, attempt stays 1
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "A: status committed on first pass" "$(get_status "$TID")" "committed"
  _expect "A: attempt == 1" "$(get_attempt "$TID")" "1"

  # Scenario B: fail, fail, pass -> committed on attempt 3
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="FAIL FAIL PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "B: status committed after retries" "$(get_status "$TID")" "committed"
  _expect "B: attempt == 3" "$(get_attempt "$TID")" "3"

  # Scenario C: always fail -> blocked at MAX_ATTEMPTS
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="FAIL FAIL FAIL FAIL FAIL FAIL" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "C: status blocked when never passing" "$(get_status "$TID")" "blocked"
  _expect "C: attempt == MAX_ATTEMPTS" "$(get_attempt "$TID")" "$MAX_ATTEMPTS"

  # Scenario D: plan blocked -> blocked immediately, attempt stays 1
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_RESULT=BLOCKED MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "D: status blocked on plan-block" "$(get_status "$TID")" "blocked"
  _expect "D: attempt == 1 (no loop)" "$(get_attempt "$TID")" "1"

  # Scenario E: implement incomplete once, then pass -> committed on attempt 2
  _reset "$TID"; set_attempt "$TID" 1
  # First attempt implement INCOMPLETE forces replan; to let attempt 2 pass we
  # need implement DONE on attempt 2. Mock can't vary impl by attempt, so model
  # the simpler invariant: INCOMPLETE always -> must end blocked.
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=INCOMPLETE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "E: persistent implement-incomplete -> blocked" "$(get_status "$TID")" "blocked"

  # Scenario F: resume skips a committed task
  _reset "$TID"; set_status "$TID" "committed"; set_attempt "$TID" 1
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="FAIL" \
    run_task "$TID" >/dev/null 2>&1
  _expect "F: committed task left untouched on resume" "$(get_status "$TID")" "committed"

  # Scenario G: rate-limit on first 2 calls, then succeeds -> committed, attempt stays 1
  _reset "$TID"; set_attempt "$TID" 1
  RATE_LIMIT_COOLDOWN=1 MAX_RATE_LIMIT_WAITS=3 MOCK_RATE_LIMIT_COUNT=2 \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "G: rate-limited then committed" "$(get_status "$TID")" "committed"
  _expect "G: attempt == 1 (rate-limit didn't burn attempts)" "$(get_attempt "$TID")" "1"

  # Scenario H: process failure blocks without burning task attempts
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_FORCE_EXIT=7 \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "H: process failure blocks for review" "$(get_status "$TID")" "blocked"
  _expect "H: process failure leaves attempt == 1" "$(get_attempt "$TID")" "1"

  # Scenario I: interrupted after planning -> resume reuses the plan and implements
  _reset "$TID"; set_status "$TID" "planning"; set_attempt "$TID" 1
  printf 'existing approved plan\n' > "$(state_dir_for "$TID")/plan.md"
  MOCK_PLAN_RESULT=BLOCKED MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "I: resume reuses existing plan" "$(get_status "$TID")" "committed"

  # Scenario J: successful transcript with project text containing 429 is not rate-limited
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_NOISY_SUCCESS=1 \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "J: successful noisy plan is not rate-limited" "$(get_status "$TID")" "committed"

  # Scenario K: prompt echoes PLAN: BLOCKED instructions before final READY
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_PLAN_INSTRUCTION_ECHO=1 \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "K: final PLAN READY wins over earlier instruction echo" "$(get_status "$TID")" "committed"

  # Scenario L: prompt echoes IMPLEMENT: DONE before final INCOMPLETE
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_IMPL_INSTRUCTION_ECHO=1 \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=INCOMPLETE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "L: final IMPLEMENT INCOMPLETE wins over earlier instruction echo" "$(get_status "$TID")" "blocked"

  # Scenario M: verify stack startup failure blocks without burning attempts
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_STACK_RESULT=FAIL \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "M: stack failure blocks for infrastructure review" "$(get_status "$TID")" "blocked"
  _expect "M: stack failure leaves attempt == 1" "$(get_attempt "$TID")" "1"
  _expect "M: stack failure is classified" "$(sed -n '2p' "$(state_dir_for "$TID")/verify.txt")" "KIND: verify_stack_failure"

  # Scenario N: Next's per-project dev-server lock is classified as stack infra.
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_STACK_RESULT=NEXT_LOCK \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "N: next dev lock blocks for infrastructure review" "$(get_status "$TID")" "blocked"
  _expect "N: next dev lock leaves attempt == 1" "$(get_attempt "$TID")" "1"
  _expect "N: next dev lock evidence is preserved" "$(grep -c 'Another next dev server is already running' "$(state_dir_for "$TID")/verify.txt")" "2"

  # Scenario O: stack-less codebase verification can proceed to commit.
  _reset "$TID"; set_attempt "$TID" 1
  MOCK_STACK_RESULT=SKIP \
  MOCK_PLAN_RESULT=READY MOCK_IMPL_RESULT=DONE MOCK_VERIFY_SCRIPT="PASS" MOCK_COMMIT_RESULT=DONE \
    run_task "$TID" >/dev/null 2>&1
  _expect "O: skipped verify stack still verifies" "$(get_status "$TID")" "committed"
  _expect "O: skipped verify stack leaves attempt == 1" "$(get_attempt "$TID")" "1"

  _restore_selftest_state
  if [ "$fails" -eq 0 ]; then
    log "SELFTEST: ALL CHECKS PASSED"; return 0
  else
    warn "SELFTEST: $fails check(s) FAILED"; return 1
  fi
}

# ── Main ─────────────────────────────────────────────────────────────────--
main() {
  case "$MODE" in
    status) print_status; exit 0 ;;
    selftest) selftest; exit $? ;;
  esac

  ensure_branch

  local started=0 t id rc
  for t in $(list_tasks); do
    id="$(task_id_from_path "$t")"
    [ -n "$ONLY_TASK" ] && [ "$id" != "$ONLY_TASK" ] && continue
    if [ -n "$FROM_TASK" ] && [ "$started" -eq 0 ]; then
      [ "$id" = "$FROM_TASK" ] && started=1 || continue
    fi
    log "=== TASK $id : $(basename "$t") ==="
    run_task "$id"; rc=$?
    if [ "$rc" -ne 0 ]; then
      warn "stopping at task $id (rc=$rc). Inspect $RUN_LOG_DIR and $(state_dir_for "$id")."
      print_status
      exit "$rc"
    fi
  done
  log "all selected tasks committed on branch $WORK_BRANCH (not pushed)."
  print_status
}

main
