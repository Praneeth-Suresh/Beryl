#!/usr/bin/env bash
# lib/common.sh — helpers for the agent driver.
# Sourced by run.sh. No side effects on source beyond function/const defs.

set -o pipefail

# ── Logging ────────────────────────────────────────────────────────────────
log()  { printf '%s [driver] %s\n' "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '%s [driver][warn] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die()  { printf '%s [driver][fatal] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; exit 1; }

# ── Paths ────────────────────────────────────────────────────────────────--
# DRIVER_DIR and REPO_ROOT are exported by run.sh before sourcing.
prompts_dir() { echo "$DRIVER_DIR/prompts"; }
tasks_dir()   { echo "$DRIVER_DIR/tasks"; }
state_root()  { echo "$DRIVER_DIR/state"; }
logs_root()   { echo "$DRIVER_DIR/logs"; }

# task_id_from_path tasks/03-foo.md -> 03
task_id_from_path() { basename "$1" | sed -E 's/^([0-9]+).*/\1/'; }
is_placeholder_task() {
  local path="$1"
  case "$(basename "$path")" in
    *-placeholder-task.md) return 0 ;;
    *) return 1 ;;
  esac
}

state_dir_for() { echo "$(state_root)/$1"; }   # arg: task id

# ── Status file helpers ──────────────────────────────────────────────────--
# status values: pending planning implementing verifying passed committed blocked
get_status() {
  local sd; sd="$(state_dir_for "$1")"
  [ -f "$sd/status" ] && cat "$sd/status" || echo "pending"
}
set_status() {
  local sd; sd="$(state_dir_for "$1")"; mkdir -p "$sd"
  printf '%s\n' "$2" > "$sd/status"
}
get_attempt() {
  local sd; sd="$(state_dir_for "$1")"
  [ -f "$sd/attempt" ] && cat "$sd/attempt" || echo "1"
}
set_attempt() {
  local sd; sd="$(state_dir_for "$1")"; mkdir -p "$sd"
  printf '%s\n' "$2" > "$sd/attempt"
}

# ── Prompt composition ───────────────────────────────────────────────────--
# read_file_safe PATH -> contents or empty
read_file_safe() { [ -f "$1" ] && cat "$1" || printf ''; }

# compose_prompt TEMPLATE_FILE  (uses exported PH_* vars for substitution)
# Placeholders are replaced via a Python one-liner (handles multi-line values,
# no jq dependency, no sed-escaping pitfalls).
compose_prompt() {
  local tmpl="$1"
  REPO_ROOT="$REPO_ROOT" WORK_BRANCH="$WORK_BRANCH" \
  STATE_DIR="$PH_STATE_DIR" ATTEMPT="$PH_ATTEMPT" MAX_ATTEMPTS="$MAX_ATTEMPTS" \
  TASK_BRIEF="$PH_TASK_BRIEF" FAILURE_CONTEXT="$PH_FAILURE_CONTEXT" \
  PLAN="$PH_PLAN" VERIFY="$PH_VERIFY" \
  VERIFY_STACK_STATUS="$PH_VERIFY_STACK_STATUS" \
  VERIFY_BASE_URL="$VERIFY_BASE_URL" VERIFY_API_URL="$VERIFY_API_URL" \
  python3 - "$tmpl" <<'PY'
import os, sys
tmpl = open(sys.argv[1]).read()
keys = ["REPO_ROOT","WORK_BRANCH","STATE_DIR","ATTEMPT","MAX_ATTEMPTS",
        "TASK_BRIEF","FAILURE_CONTEXT","PLAN","VERIFY",
        "VERIFY_STACK_STATUS","VERIFY_BASE_URL","VERIFY_API_URL"]
for k in keys:
    tmpl = tmpl.replace("{{%s}}" % k, os.environ.get(k, ""))
sys.stdout.write(tmpl)
PY
}

# ── Sentinel parsing ─────────────────────────────────────────────────────--
# last_sentinel LOGFILE REGEX -> the last matching line (or empty)
last_sentinel() { grep -E "$2" "$1" 2>/dev/null | tail -n1; }

last_plan_sentinel() {
  last_sentinel "$1" '^PLAN: (READY|BLOCKED( |$))'
}

last_implement_sentinel() {
  last_sentinel "$1" '^IMPLEMENT: (DONE|INCOMPLETE( |$))'
}

last_commit_sentinel() {
  last_sentinel "$1" '^COMMIT: (DONE|SKIPPED)( |$)'
}

phase_passed_plan()      { [ "$(last_plan_sentinel "$1")" = "PLAN: READY" ]; }
phase_blocked_plan()     { last_plan_sentinel "$1" | grep -qE '^PLAN: BLOCKED( |$)'; }
phase_done_implement()   { [ "$(last_implement_sentinel "$1")" = "IMPLEMENT: DONE" ]; }
# verify uses the verify.txt file's first line as the source of truth
verify_passed() { head -n1 "$1" 2>/dev/null | grep -qE '^VERIFY: PASS'; }
verify_failed() { head -n1 "$1" 2>/dev/null | grep -qE '^VERIFY: FAIL'; }
phase_done_commit()      { last_commit_sentinel "$1" | grep -qE '^COMMIT: (DONE|SKIPPED)( |$)'; }

# ── Rate limit detection ──────────────────────────────────────────────────--
is_rate_limited() {
  local logfile="$1"
  tail -n 120 "$logfile" 2>/dev/null \
    | grep -qiE '(Error: )?(429 Too Many Requests|rate limit exceeded|too many requests|try again later|quota exceeded)'
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ── Driver config parsing and runtime cleanup ─────────────────────────────
driver_bool_value() {
  local name="$1" value="$2"
  case "${value,,}" in
    1|true|yes|on) echo "true" ;;
    0|false|no|off) echo "false" ;;
    *) die "invalid $name='$value'; expected one of true/false, yes/no, on/off, or 1/0" ;;
  esac
}

path_is_git_tracked() {
  local path="$1" rel
  case "$path" in
    "$REPO_ROOT"/*) rel="${path#"$REPO_ROOT"/}" ;;
    *) rel="$path" ;;
  esac
  git -C "$REPO_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1
}

clear_runtime_root() {
  local root="$1" removed=0 preserved=0 item
  mkdir -p "$root"

  while IFS= read -r -d '' item; do
    if path_is_git_tracked "$item"; then
      preserved=$((preserved + 1))
      continue
    fi

    if [ -d "$item" ] && [ ! -L "$item" ]; then
      if rmdir -- "$item" 2>/dev/null; then
        removed=$((removed + 1))
      fi
    elif rm -f -- "$item"; then
      removed=$((removed + 1))
    fi
  done < <(find "$root" -mindepth 1 -depth -print0)

  mkdir -p "$root"
  printf '%s %s\n' "$removed" "$preserved"
}

flush_driver_runtime() {
  local state_counts logs_counts
  state_counts="$(clear_runtime_root "$(state_root)")"
  logs_counts="$(clear_runtime_root "$(logs_root)")"
  printf '%s %s\n' "$state_counts" "$logs_counts"
}

# ── Agent selection ───────────────────────────────────────────────────────--
# The driver supports multiple coding agents. DRIVER_AGENT picks one; when it
# is unset on an interactive terminal the user chooses from a menu and the
# choice is persisted to config.env for future runs.
driver_agent_bin() {
  case "${DRIVER_AGENT:-codex}" in
    codex)  echo "${CODEX_BIN:-codex}" ;;
    claude) echo "${CLAUDE_BIN:-claude}" ;;
    gemini) echo "${GEMINI_BIN:-gemini}" ;;
    custom) tokenize_extra_args "${CUSTOM_AGENT_CMD:-}"; echo "${EXTRA_ARG_TOKENS[0]:-}" ;;
  esac
}

persist_driver_agent() {
  local cfg="$DRIVER_DIR/config.env"
  if [ ! -f "$cfg" ]; then
    printf '# Local driver overrides (gitignored). See config.example.env.\n' > "$cfg"
  fi
  printf 'DRIVER_AGENT="%s"\n' "$DRIVER_AGENT" >> "$cfg"
  log "saved DRIVER_AGENT=\"$DRIVER_AGENT\" to .beryl/driver/config.env"
}

select_driver_agent() {
  case "${DRIVER_AGENT:-}" in
    codex|claude|gemini|custom) ;;
    "")
      if [ "${DRIVER_MOCK:-0}" = "1" ]; then
        DRIVER_AGENT="codex"; export DRIVER_AGENT; return 0
      fi
      if [ ! -t 0 ]; then
        die "DRIVER_AGENT is not set. Set it in .beryl/driver/config.env (codex, claude, gemini, or custom), or run the driver from an interactive terminal to choose."
      fi
      printf '\nSelect the coding agent the driver should run:\n' >&2
      printf '  1) codex   - OpenAI Codex CLI (codex exec)\n' >&2
      printf '  2) claude  - Claude Code CLI (claude -p)\n' >&2
      printf '  3) gemini  - Gemini CLI (gemini -p)\n' >&2
      printf '  4) custom  - your own command via CUSTOM_AGENT_CMD\n' >&2
      local choice
      while :; do
        printf 'Choice [1-4]: ' >&2
        read -r choice || die "no agent selected"
        case "$choice" in
          1|codex)  DRIVER_AGENT="codex";  break ;;
          2|claude) DRIVER_AGENT="claude"; break ;;
          3|gemini) DRIVER_AGENT="gemini"; break ;;
          4|custom) DRIVER_AGENT="custom"; break ;;
          *) printf 'invalid choice: %s\n' "$choice" >&2 ;;
        esac
      done
      export DRIVER_AGENT
      persist_driver_agent
      ;;
    *)
      die "invalid DRIVER_AGENT='${DRIVER_AGENT}'; expected codex, claude, gemini, or custom"
      ;;
  esac

  if [ "${DRIVER_MOCK:-0}" != "1" ]; then
    if [ "$DRIVER_AGENT" = "custom" ] && [ -z "${CUSTOM_AGENT_CMD:-}" ]; then
      die "DRIVER_AGENT=\"custom\" requires CUSTOM_AGENT_CMD in .beryl/driver/config.env"
    fi
    local bin; bin="$(driver_agent_bin)"
    command_exists "$bin" || die "agent binary '$bin' for DRIVER_AGENT=\"$DRIVER_AGENT\" is not on PATH"
  fi
}

# ── Agent safety gates ────────────────────────────────────────────────────--
# Unattended mode (no approval prompts + writable filesystem) must be an
# explicit, acknowledged opt-in, not a silent default — whichever agent runs.
require_unattended_ack() {
  [ "${DRIVER_MOCK:-0}" = "1" ] && return 0
  local why=""
  case "${DRIVER_AGENT:-codex}" in
    codex)
      [ "${CODEX_APPROVAL:-}" = "never" ] && why="CODEX_APPROVAL=\"never\""
      ;;
    claude)
      [ "${CLAUDE_PERMISSION_MODE:-bypassPermissions}" = "bypassPermissions" ] && why="CLAUDE_PERMISSION_MODE=\"bypassPermissions\""
      ;;
    gemini)
      [ "${GEMINI_APPROVAL_MODE:-yolo}" = "yolo" ] && why="GEMINI_APPROVAL_MODE=\"yolo\""
      ;;
    custom)
      why="DRIVER_AGENT=\"custom\" (the driver cannot verify its approval behavior)"
      ;;
  esac
  [ -n "$why" ] || return 0
  if [ "$(driver_bool_value "DRIVER_UNATTENDED_OK" "${DRIVER_UNATTENDED_OK:-false}")" != "true" ]; then
    die "$why runs a code-writing agent with no human approval and filesystem write access. If you accept that (ideally inside a container/VM), set DRIVER_UNATTENDED_OK=\"true\" in .beryl/driver/config.env."
  fi
  warn "unattended mode enabled: agent=${DRIVER_AGENT:-codex} ($why). Task briefs, prompts, and config.env are trusted inputs — review WORK_BRANCH diffs before pushing."
}

# Whitespace-split CODEX_EXTRA_ARGS into EXTRA_ARG_TOKENS with a strict
# per-token charset, so config.env content cannot expand into quoting tricks
# or shell metacharacters.
tokenize_extra_args() {
  local raw="$1" tok
  EXTRA_ARG_TOKENS=()
  read -r -a EXTRA_ARG_TOKENS <<< "$raw"
  for tok in "${EXTRA_ARG_TOKENS[@]}"; do
    [[ "$tok" =~ ^[A-Za-z0-9._=/,:@+-]+$ ]] \
      || die "CODEX_EXTRA_ARGS contains an unsupported token: $tok (allowed: letters, digits, ._=/,:@+-)"
  done
}

# ── Agent invocation ──────────────────────────────────────────────────────--
# build_agent_cmd PROMPT -> fills AGENT_CMD with the full per-agent command.
# Every preset must run headlessly, print its transcript to stdout, and exit
# non-zero on failure; the prompt is always the final argument.
build_agent_cmd() {
  local prompt="$1"
  AGENT_CMD=()
  case "${DRIVER_AGENT:-codex}" in
    codex)
      AGENT_CMD=("${CODEX_BIN:-codex}" exec -C "$REPO_ROOT")
      [ -n "${CODEX_MODEL:-}" ] && AGENT_CMD+=(--model "$CODEX_MODEL")
      [ -n "${CODEX_PROFILE:-}" ] && AGENT_CMD+=(--profile "$CODEX_PROFILE")
      [ -n "${CODEX_SANDBOX:-}" ] && AGENT_CMD+=(--sandbox "$CODEX_SANDBOX")
      [ -n "${CODEX_APPROVAL:-}" ] && AGENT_CMD+=(-c "approval_policy=\"$CODEX_APPROVAL\"")
      tokenize_extra_args "${CODEX_EXTRA_ARGS:-}"
      AGENT_CMD+=("${EXTRA_ARG_TOKENS[@]}")
      ;;
    claude)
      AGENT_CMD=("${CLAUDE_BIN:-claude}" -p)
      [ -n "${CLAUDE_MODEL:-}" ] && AGENT_CMD+=(--model "$CLAUDE_MODEL")
      if [ "${CLAUDE_PERMISSION_MODE:-bypassPermissions}" = "bypassPermissions" ]; then
        AGENT_CMD+=(--dangerously-skip-permissions)
      else
        AGENT_CMD+=(--permission-mode "$CLAUDE_PERMISSION_MODE")
      fi
      tokenize_extra_args "${CLAUDE_EXTRA_ARGS:-}"
      AGENT_CMD+=("${EXTRA_ARG_TOKENS[@]}")
      ;;
    gemini)
      AGENT_CMD=("${GEMINI_BIN:-gemini}")
      [ -n "${GEMINI_MODEL:-}" ] && AGENT_CMD+=(--model "$GEMINI_MODEL")
      AGENT_CMD+=(--approval-mode "${GEMINI_APPROVAL_MODE:-yolo}")
      tokenize_extra_args "${GEMINI_EXTRA_ARGS:-}"
      AGENT_CMD+=("${EXTRA_ARG_TOKENS[@]}")
      AGENT_CMD+=(-p)
      ;;
    custom)
      [ -n "${CUSTOM_AGENT_CMD:-}" ] || die "DRIVER_AGENT=\"custom\" requires CUSTOM_AGENT_CMD in .beryl/driver/config.env"
      tokenize_extra_args "${CUSTOM_AGENT_CMD}"
      AGENT_CMD=("${EXTRA_ARG_TOKENS[@]}")
      ;;
    *)
      die "invalid DRIVER_AGENT='${DRIVER_AGENT:-}'; expected codex, claude, gemini, or custom"
      ;;
  esac
  AGENT_CMD+=("$prompt")
}

# run_agent PROMPT LOGFILE -> exit code of the session (tee'd to LOGFILE)
run_agent() {
  local prompt="$1" logfile="$2"
  mkdir -p "$(dirname "$logfile")"
  if [ "${DRIVER_MOCK:-0}" = "1" ]; then
    mock_agent "$prompt" | tee "$logfile"
    return "${PIPESTATUS[0]}"
  fi
  build_agent_cmd "$prompt"
  "${AGENT_CMD[@]}" 2>&1 | tee "$logfile"
  return "${PIPESTATUS[0]}"
}

# ── Isolated dev stack for verification ──────────────────────────────────--
# These helpers support the legacy backend/frontend verifier. The driver starts
# that stack only when VERIFY_STACK_MODE requires it or auto-detection finds it.
VSTACK_BACKEND_PID=""
VSTACK_FRONTEND_PID=""
VSTACK_FRONTEND_DIST_DIR=""
VERIFY_STACK_STATUS="${VERIFY_STACK_STATUS:-not evaluated}"

has_legacy_verify_stack() {
  [ -d "$REPO_ROOT/backend" ] \
    && [ -d "$REPO_ROOT/frontend" ] \
    && [ -x "$REPO_ROOT/.venv/bin/python" ]
}

should_start_verify_stack() {
  if [ "${DRIVER_MOCK:-0}" = "1" ]; then
    case "${MOCK_STACK_RESULT:-OK}" in
      SKIP)
        VERIFY_STACK_STATUS="[mock] skipped by MOCK_STACK_RESULT=SKIP"
        export VERIFY_STACK_STATUS
        return 1
        ;;
      *)
        VERIFY_STACK_STATUS="[mock] starting mocked verifier stack"
        export VERIFY_STACK_STATUS
        return 0
        ;;
    esac
  fi

  case "${VERIFY_STACK_MODE:-auto}" in
    always)
      VERIFY_STACK_STATUS="required by VERIFY_STACK_MODE=always; starting legacy backend/frontend verifier"
      export VERIFY_STACK_STATUS
      return 0
      ;;
    never)
      VERIFY_STACK_STATUS="skipped by VERIFY_STACK_MODE=never"
      export VERIFY_STACK_STATUS
      return 1
      ;;
    auto)
      if has_legacy_verify_stack; then
        VERIFY_STACK_STATUS="auto-detected legacy backend/frontend verifier; starting stack"
        export VERIFY_STACK_STATUS
        return 0
      fi
      VERIFY_STACK_STATUS="skipped by VERIFY_STACK_MODE=auto; no legacy backend/frontend verifier detected"
      export VERIFY_STACK_STATUS
      return 1
      ;;
    *)
      die "invalid VERIFY_STACK_MODE='${VERIFY_STACK_MODE:-}'; expected auto, always, or never"
      ;;
  esac
}

port_is_listening() {
  local port="$1"
  python3 - "$port" <<'PY' >/dev/null 2>&1
import socket
import sys

port = int(sys.argv[1])
for host in ("127.0.0.1", "::1"):
    family = socket.AF_INET6 if ":" in host else socket.AF_INET
    try:
        with socket.socket(family, socket.SOCK_STREAM) as sock:
            sock.settimeout(0.25)
            if sock.connect_ex((host, port)) == 0:
                sys.exit(0)
    except OSError:
        pass
sys.exit(1)
PY
}

process_is_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

choose_verify_ports() {
  local backend_port="${VERIFY_BACKEND_PORT_SETTING:-${VERIFY_BACKEND_PORT:-8100}}"
  local frontend_port="${VERIFY_FRONTEND_PORT_SETTING:-${VERIFY_FRONTEND_PORT:-3100}}"
  local chosen
  chosen="$(
    python3 - "$backend_port" "$frontend_port" <<'PY'
import socket
import sys

backend_arg, frontend_arg = sys.argv[1], sys.argv[2]
sockets = []

def fixed_port(value: str) -> int | None:
    if value.lower() == "auto":
        return None
    try:
        port = int(value)
    except ValueError:
        raise SystemExit(f"invalid verify port: {value!r}")
    if port <= 0 or port > 65535:
        raise SystemExit(f"invalid verify port: {value!r}")
    return port

def choose_port(excluded: set[int]) -> int:
    for _ in range(50):
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
        if port not in excluded:
            sockets.append(sock)
            excluded.add(port)
            return port
        sock.close()
    raise SystemExit("could not allocate unique verify port")

excluded: set[int] = set()
backend = fixed_port(backend_arg)
if backend is None:
    backend = choose_port(excluded)
else:
    excluded.add(backend)

frontend = fixed_port(frontend_arg)
if frontend is None:
    frontend = choose_port(excluded)
else:
    excluded.add(frontend)

print(f"{backend} {frontend}")
PY
  )" || return 1
  VERIFY_BACKEND_PORT="${chosen%% *}"
  VERIFY_FRONTEND_PORT="${chosen##* }"
  VERIFY_API_URL="http://localhost:${VERIFY_BACKEND_PORT}"
  VERIFY_BASE_URL="http://localhost:${VERIFY_FRONTEND_PORT}"
  export VERIFY_BACKEND_PORT VERIFY_FRONTEND_PORT VERIFY_API_URL VERIFY_BASE_URL
}

log_has_bind_failure() {
  local file="$1"
  [ -f "$file" ] && grep -qiE 'EADDRINUSE|address already in use|listen .*already in use' "$file"
}

log_has_next_lock_failure() {
  local file="$1"
  [ -f "$file" ] && grep -qi 'Another next dev server is already running' "$file"
}

tail_log_file() {
  local file="$1" lines="${2:-40}"
  if [ -f "$file" ]; then
    tail -n "$lines" "$file"
  else
    printf 'log file unavailable: %s\n' "$file"
  fi
}

write_verify_stack_failure() {
  local reason="$1"
  mkdir -p "$RUN_LOG_DIR"
  {
    printf 'KIND: verify_stack_failure\n'
    printf 'Verification stack startup failed: %s\n' "$reason"
    if [ -f "$RUN_LOG_DIR/verify-backend.log" ]; then
      printf '\n--- verify-backend.log tail ---\n'
      tail_log_file "$RUN_LOG_DIR/verify-backend.log" 40
    fi
    if [ -f "$RUN_LOG_DIR/verify-frontend.log" ]; then
      printf '\n--- verify-frontend.log tail ---\n'
      tail_log_file "$RUN_LOG_DIR/verify-frontend.log" 40
    fi
  } > "$RUN_LOG_DIR/verify-stack-failure.txt"
  warn "$reason"
}

start_verify_stack() {
  if [ "${DRIVER_MOCK:-0}" = "1" ]; then
    if [ "${MOCK_STACK_RESULT:-OK}" = "NEXT_LOCK" ]; then
      mkdir -p "$RUN_LOG_DIR"
      printf 'Another next dev server is already running.\n' > "$RUN_LOG_DIR/verify-frontend.log"
      write_verify_stack_failure "[mock] frontend verify process hit Next dev lock: Another next dev server is already running"
      return 1
    fi
    if [ "${MOCK_STACK_RESULT:-OK}" = "FAIL" ]; then
      write_verify_stack_failure "[mock] verify stack startup failed"
      return 1
    fi
    log "[mock] skip start_verify_stack"; return 0
  fi
  if ! choose_verify_ports; then
    write_verify_stack_failure "failed to resolve verification ports"
    return 1
  fi
  log "starting isolated verify stack (fe:$VERIFY_FRONTEND_PORT be:$VERIFY_BACKEND_PORT)"
  VSTACK_BACKEND_PID=""
  VSTACK_FRONTEND_PID=""
  VSTACK_FRONTEND_DIST_DIR=".next/driver-${RUN_ID}"
  : > "$RUN_LOG_DIR/verify-backend.log"
  : > "$RUN_LOG_DIR/verify-frontend.log"
  rm -f "$RUN_LOG_DIR/.be.pid" "$RUN_LOG_DIR/.fe.pid" "$RUN_LOG_DIR/verify-stack-failure.txt"
  log "verify frontend NEXT_DIST_DIR=$VSTACK_FRONTEND_DIST_DIR"

  if port_is_listening "$VERIFY_BACKEND_PORT"; then
    write_verify_stack_failure "backend verify port $VERIFY_BACKEND_PORT is already listening"
    return 1
  fi
  if port_is_listening "$VERIFY_FRONTEND_PORT"; then
    write_verify_stack_failure "frontend verify port $VERIFY_FRONTEND_PORT is already listening"
    return 1
  fi

  # Copy dev DB so verification mutations don't touch canonical data.
  if [ -f "$REPO_ROOT/$SOURCE_DB" ]; then
    cp -f "$REPO_ROOT/$SOURCE_DB" "$REPO_ROOT/$VERIFY_DB"
  fi
  if command_exists setsid; then
    ( cd "$REPO_ROOT/backend" && \
      CORS_ALLOWED_ORIGINS="$VERIFY_BASE_URL" \
      DATABASE_URL="sqlite:///./$(basename "$VERIFY_DB")" \
      ENVIRONMENT=development \
      setsid "$REPO_ROOT/.venv/bin/python" -m uvicorn src.main:app \
        --host "${VERIFY_BIND_HOST:-127.0.0.1}" --port "$VERIFY_BACKEND_PORT" \
        > "$RUN_LOG_DIR/verify-backend.log" 2>&1 & echo $! > "$RUN_LOG_DIR/.be.pid" )
  else
    ( cd "$REPO_ROOT/backend" && \
      CORS_ALLOWED_ORIGINS="$VERIFY_BASE_URL" \
      DATABASE_URL="sqlite:///./$(basename "$VERIFY_DB")" \
      ENVIRONMENT=development \
      "$REPO_ROOT/.venv/bin/python" -m uvicorn src.main:app \
        --host "${VERIFY_BIND_HOST:-127.0.0.1}" --port "$VERIFY_BACKEND_PORT" \
        > "$RUN_LOG_DIR/verify-backend.log" 2>&1 & echo $! > "$RUN_LOG_DIR/.be.pid" )
  fi
  VSTACK_BACKEND_PID="$(cat "$RUN_LOG_DIR/.be.pid")"
  sleep 1
  if log_has_bind_failure "$RUN_LOG_DIR/verify-backend.log"; then
    write_verify_stack_failure "backend verify process could not bind port $VERIFY_BACKEND_PORT"
    return 1
  fi
  if ! process_is_alive "$VSTACK_BACKEND_PID"; then
    write_verify_stack_failure "backend verify process exited during startup (pid $VSTACK_BACKEND_PID)"
    return 1
  fi

  if command_exists setsid; then
    ( cd "$REPO_ROOT/frontend" && \
      printf 'NEXT_DIST_DIR=%s\nVERIFY_BASE_URL=%s\nVERIFY_API_URL=%s\n' \
        "$VSTACK_FRONTEND_DIST_DIR" "$VERIFY_BASE_URL" "$VERIFY_API_URL" \
        > "$RUN_LOG_DIR/verify-frontend.log" && \
      NEXT_PUBLIC_API_URL="$VERIFY_API_URL" \
      NEXT_DIST_DIR="$VSTACK_FRONTEND_DIST_DIR" \
      setsid npx next dev -H "${VERIFY_BIND_HOST:-127.0.0.1}" -p "$VERIFY_FRONTEND_PORT" \
        >> "$RUN_LOG_DIR/verify-frontend.log" 2>&1 & echo $! > "$RUN_LOG_DIR/.fe.pid" )
  else
    ( cd "$REPO_ROOT/frontend" && \
      printf 'NEXT_DIST_DIR=%s\nVERIFY_BASE_URL=%s\nVERIFY_API_URL=%s\n' \
        "$VSTACK_FRONTEND_DIST_DIR" "$VERIFY_BASE_URL" "$VERIFY_API_URL" \
        > "$RUN_LOG_DIR/verify-frontend.log" && \
      NEXT_PUBLIC_API_URL="$VERIFY_API_URL" \
      NEXT_DIST_DIR="$VSTACK_FRONTEND_DIST_DIR" \
      npx next dev -H "${VERIFY_BIND_HOST:-127.0.0.1}" -p "$VERIFY_FRONTEND_PORT" \
        >> "$RUN_LOG_DIR/verify-frontend.log" 2>&1 & echo $! > "$RUN_LOG_DIR/.fe.pid" )
  fi
  VSTACK_FRONTEND_PID="$(cat "$RUN_LOG_DIR/.fe.pid")"
  sleep 1
  if log_has_bind_failure "$RUN_LOG_DIR/verify-frontend.log"; then
    write_verify_stack_failure "frontend verify process could not bind port $VERIFY_FRONTEND_PORT"
    return 1
  fi
  if log_has_next_lock_failure "$RUN_LOG_DIR/verify-frontend.log"; then
    write_verify_stack_failure "frontend verify process hit Next dev lock despite private NEXT_DIST_DIR=$VSTACK_FRONTEND_DIST_DIR"
    return 1
  fi
  if ! process_is_alive "$VSTACK_FRONTEND_PID"; then
    write_verify_stack_failure "frontend verify process exited during startup (pid $VSTACK_FRONTEND_PID)"
    return 1
  fi

  # Wait for readiness. If either process exits, fail before browser checks.
  local i
  for i in $(seq 1 30); do
    if ! process_is_alive "$VSTACK_BACKEND_PID"; then
      write_verify_stack_failure "backend verify process exited before readiness (pid $VSTACK_BACKEND_PID)"
      return 1
    fi
    if log_has_bind_failure "$RUN_LOG_DIR/verify-backend.log"; then
      write_verify_stack_failure "backend verify process hit bind failure during readiness"
      return 1
    fi
    if ! process_is_alive "$VSTACK_FRONTEND_PID"; then
      write_verify_stack_failure "frontend verify process exited before readiness (pid $VSTACK_FRONTEND_PID)"
      return 1
    fi
    if log_has_bind_failure "$RUN_LOG_DIR/verify-frontend.log"; then
      write_verify_stack_failure "frontend verify process hit bind failure during readiness"
      return 1
    fi
    if log_has_next_lock_failure "$RUN_LOG_DIR/verify-frontend.log"; then
      write_verify_stack_failure "frontend verify process hit Next dev lock despite private NEXT_DIST_DIR=$VSTACK_FRONTEND_DIST_DIR"
      return 1
    fi
    if curl -f -o /dev/null -s "$VERIFY_API_URL/health" 2>/dev/null \
       && curl -f -o /dev/null -s "$VERIFY_BASE_URL/" 2>/dev/null; then
      log "verify stack ready"; return 0
    fi
    sleep 2
  done
  write_verify_stack_failure "verify stack did not report ready within timeout"
  return 1
}

terminate_pid_group() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  kill "-$pid" 2>/dev/null || true
  kill "$pid" 2>/dev/null || true
  sleep 1
  if process_is_alive "$pid"; then
    kill -9 "-$pid" 2>/dev/null || true
    kill -9 "$pid" 2>/dev/null || true
  fi
}

stop_verify_stack() {
  [ "${DRIVER_MOCK:-0}" = "1" ] && return 0
  local had_stack=0
  [ -n "$VSTACK_FRONTEND_PID" ] && had_stack=1
  [ -n "$VSTACK_BACKEND_PID" ] && had_stack=1
  terminate_pid_group "$VSTACK_FRONTEND_PID"
  terminate_pid_group "$VSTACK_BACKEND_PID"
  VSTACK_FRONTEND_PID=""
  VSTACK_BACKEND_PID=""
  rm -f "$REPO_ROOT/$VERIFY_DB" 2>/dev/null
  if [ -n "$VSTACK_FRONTEND_DIST_DIR" ]; then
    case "$VSTACK_FRONTEND_DIST_DIR" in
      .next/driver-*) rm -rf "$REPO_ROOT/frontend/$VSTACK_FRONTEND_DIST_DIR" 2>/dev/null ;;
      *) warn "refusing to remove unexpected verifier NEXT_DIST_DIR=$VSTACK_FRONTEND_DIST_DIR" ;;
    esac
    VSTACK_FRONTEND_DIST_DIR=""
  fi
  [ "$had_stack" -eq 1 ] && log "verify stack stopped"
}

# ── git helpers ──────────────────────────────────────────────────────────--
ensure_branch() {
  [ "${DRIVER_MOCK:-0}" = "1" ] && { log "[mock] skip ensure_branch"; return 0; }
  cd "$REPO_ROOT" || die "no repo root"
  if ! git rev-parse --verify "$WORK_BRANCH" >/dev/null 2>&1; then
    log "creating branch $WORK_BRANCH from $BASE_BRANCH"
    git checkout -b "$WORK_BRANCH" "$BASE_BRANCH" || die "branch create failed"
  else
    git checkout "$WORK_BRANCH" || die "branch checkout failed"
  fi
}

# ── Mock responder (DRIVER_MOCK=1) ───────────────────────────────────────--
# Deterministic fake agent. Behavior is driven by env knobs set by the selftest:
#   MOCK_PLAN_RESULT   = READY|BLOCKED
#   MOCK_IMPL_RESULT   = DONE|INCOMPLETE
#   MOCK_VERIFY_SCRIPT = space-separated per-attempt verdicts, e.g. "FAIL FAIL PASS"
#   MOCK_COMMIT_RESULT = DONE|SKIPPED
# It detects the phase from a marker line in the prompt and writes the same
# state files a real agent would (plan.md / verify.txt), so run.sh's file-based
# control flow is exercised exactly as in real mode.
mock_agent() {
  local prompt="$1"
  # STATE_DIR is embedded in the prompt (we also have PH_STATE_DIR in env).
  local sd="$PH_STATE_DIR"
  mkdir -p "$sd"
  # Rate-limit simulation: first MOCK_RATE_LIMIT_COUNT calls return 429.
  if [ "${MOCK_RATE_LIMIT_COUNT:-0}" -gt 0 ]; then
    local rl_file="$sd/.mock_rl_calls"
    local rl_so_far; rl_so_far="$(cat "$rl_file" 2>/dev/null || echo 0)"
    if [ "$rl_so_far" -lt "$MOCK_RATE_LIMIT_COUNT" ]; then
      printf '%s\n' "$((rl_so_far + 1))" > "$rl_file"
      echo "Error: 429 Too Many Requests - rate limit exceeded"
      return 1
    fi
  fi
  if [ "${MOCK_FORCE_EXIT:-0}" -ne 0 ]; then
    echo "[mock] forced process failure"
    return "$MOCK_FORCE_EXIT"
  fi
  if printf '%s' "$prompt" | grep -q 'PLAN phase'; then
    echo "[mock] planning"
    if [ "${MOCK_PLAN_NOISY_SUCCESS:-0}" -ne 0 ]; then
      echo "normal project text: status === 429 and CDN rate limiting"
    fi
    if [ "${MOCK_PLAN_INSTRUCTION_ECHO:-0}" -ne 0 ]; then
      echo "PLAN: BLOCKED <one-line reason>"
    fi
    printf 'mock plan for attempt %s\n' "$PH_ATTEMPT" > "$sd/plan.md"
    if [ "${MOCK_PLAN_RESULT:-READY}" = "BLOCKED" ]; then
      echo "PLAN: BLOCKED mock-block"; else echo "PLAN: READY"; fi
  elif printf '%s' "$prompt" | grep -q 'IMPLEMENT phase'; then
    echo "[mock] implementing"
    if [ "${MOCK_IMPL_INSTRUCTION_ECHO:-0}" -ne 0 ]; then
      echo "IMPLEMENT: DONE"
    fi
    if [ "${MOCK_IMPL_RESULT:-DONE}" = "INCOMPLETE" ]; then
      echo "IMPLEMENT: INCOMPLETE mock-incomplete"; else echo "IMPLEMENT: DONE"; fi
  elif printf '%s' "$prompt" | grep -q 'VERIFY phase'; then
    # pick verdict for this attempt from MOCK_VERIFY_SCRIPT (1-indexed)
    local idx="$PH_ATTEMPT"; local verdict
    verdict="$(echo "${MOCK_VERIFY_SCRIPT:-PASS}" | awk -v i="$idx" '{print $i}')"
    [ -z "$verdict" ] && verdict="$(echo "${MOCK_VERIFY_SCRIPT:-PASS}" | awk '{print $NF}')"
    echo "[mock] verifying attempt $idx -> $verdict"
    if [ "$verdict" = "PASS" ]; then
      printf 'VERIFY: PASS\nmock confirmed\n' > "$sd/verify.txt"
      echo "VERIFY: PASS"
    else
      printf 'VERIFY: FAIL\n1. mock criterion unmet (attempt %s)\n' "$idx" > "$sd/verify.txt"
      echo "VERIFY: FAIL"
    fi
  elif printf '%s' "$prompt" | grep -q 'COMMIT phase'; then
    echo "[mock] committing"
    if [ "${MOCK_COMMIT_INSTRUCTION_ECHO:-0}" -ne 0 ]; then
      echo "COMMIT: DONE <short-sha>"
    fi
    if [ "${MOCK_COMMIT_RESULT:-DONE}" = "SKIPPED" ]; then
      echo "COMMIT: SKIPPED mock-skip"; else echo "COMMIT: DONE deadbeef"; fi
  else
    echo "[mock] unknown phase"; return 2
  fi
}
