#!/usr/bin/env bash
set -u

DRIVER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export DRIVER_DIR

# shellcheck disable=SC1090
. "$DRIVER_DIR/config.example.env"
if [ -f "$DRIVER_DIR/config.env" ]; then
  # shellcheck disable=SC1090
  . "$DRIVER_DIR/config.env"
fi

# shellcheck disable=SC1091
. "$DRIVER_DIR/lib/common.sh"

MODE="run"
ONLY_TASK=""
FROM_TASK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) MODE="selftest"; shift ;;
    --task) ONLY_TASK="$2"; shift 2 ;;
    --from) FROM_TASK="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage:
  bash .beryl/driver/optimize-worktrees.sh [--task NN|--from NN]
  bash .beryl/driver/optimize-worktrees.sh --selftest

Creates optional optimizer state under .beryl/driver/state/optimization/.
EOF
      exit 0
      ;;
    *) die "unknown arg: $1" ;;
  esac
done

optimizer_py="$DRIVER_DIR/lib/worktree_optimizer.py"

if [ "$MODE" = "selftest" ]; then
  exec python3 "$optimizer_py" selftest
fi

optimization_state_dir() { echo "$(state_root)/optimization"; }

json_get_parallelizable() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print("true" if json.load(fh).get("parallelizable") else "false")
PY
}

json_parallel_wave_tasks() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
seen = set()
for wave in data.get("waves", []):
    if len(wave) <= 1:
        continue
    for task_id in wave:
        if task_id not in seen:
            seen.add(task_id)
            print(task_id)
PY
}

safe_path_part() {
  printf '%s' "$1" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

write_status() {
  local status="$1" detail="$2"
  {
    printf 'OPTIMIZE_WORKTREES: %s\n' "$status"
    [ -n "$detail" ] && printf '%s\n' "$detail"
  } > "$(optimization_state_dir)/status"
}

compose_optimizer_prompt() {
  local template="$1" tasks_payload="$2"
  python3 - "$template" "$tasks_payload" <<'PY'
import json
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
payload = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
tasks = payload.get("tasks", [])
summary = {"tasks": [{"id": task.get("id", ""), "title": task.get("title", ""), "path": task.get("path", "")} for task in tasks]}
briefs = []
for task in tasks:
    task_id = task.get("id", "")
    briefs.append(f"<<<TASK_{task_id}\n{task.get('brief', '')}\nTASK_{task_id}")
text = text.replace("{{TASKS_JSON}}", json.dumps(summary, indent=2, sort_keys=True))
text = text.replace("{{TASK_BRIEFS}}", "\n\n".join(briefs))
sys.stdout.write(text)
PY
}

create_worktrees() {
  local verified_json="$1" worktrees_file="$2" run_label="$3"
  local args=(
    prepare-worktrees
    --verified-json "$verified_json"
    --output "$worktrees_file"
    --worktree-root "${DRIVER_WORKTREE_ROOT}/${run_label}"
    --work-branch "$WORK_BRANCH"
    --repo-root "$REPO_ROOT"
  )
  [ "${DRIVER_MOCK:-0}" = "1" ] && args+=(--mock)
  python3 "$optimizer_py" "${args[@]}"
}

run_optimizer() {
  local sd tasks_with_briefs tasks_summary raw_transcript raw_json verified_json waves_txt worktrees_txt status_file run_label log_file prompt
  local selection_args=()
  sd="$(optimization_state_dir)"
  mkdir -p "$sd"
  tasks_with_briefs="$sd/tasks.with-briefs.json"
  tasks_summary="$sd/tasks.json"
  raw_transcript="$sd/dag.raw-transcript.txt"
  raw_json="$sd/dag.raw.json"
  verified_json="$sd/dag.verified.json"
  waves_txt="$sd/waves.txt"
  worktrees_txt="$sd/worktrees.txt"
  status_file="$sd/status"
  run_label="${RUN_ID:-$(date '+%Y%m%d-%H%M%S')}"
  [ -n "$ONLY_TASK" ] && selection_args+=(--task "$ONLY_TASK")
  [ -n "$FROM_TASK" ] && selection_args+=(--from "$FROM_TASK")

  : > "$status_file"
  python3 "$optimizer_py" list --driver-dir "$DRIVER_DIR" --output "$tasks_with_briefs" --include-briefs "${selection_args[@]}" || {
    write_status "FAIL" "Could not collect selected tasks."
    return 1
  }
  python3 "$optimizer_py" list --driver-dir "$DRIVER_DIR" --output "$tasks_summary" "${selection_args[@]}" || {
    write_status "FAIL" "Could not write selected task summary."
    return 1
  }

  if [ "${DRIVER_MOCK:-0}" = "1" ]; then
    python3 "$optimizer_py" mock-dag --tasks-json "$tasks_summary" --output "$raw_json" || {
      write_status "FAIL" "Mock DAG generation failed."
      return 1
    }
    printf '[mock] independent task DAG written to %s\n' "$raw_json" > "$raw_transcript"
  else
    select_driver_agent
    require_unattended_ack
    prompt="$(compose_optimizer_prompt "$(prompts_dir)/optimize.md" "$tasks_with_briefs")"
    log_file="${RUN_LOG_DIR:-$(logs_root)/optimization}/optimize-worktrees.log"
    export PH_STATE_DIR="$sd" PH_ATTEMPT="1"
    if ! run_agent "$prompt" "$log_file"; then
      write_status "FAIL" "Optimizer agent failed; see $log_file."
      return 1
    fi
    cp "$log_file" "$raw_transcript"
    if ! python3 "$optimizer_py" extract-json --input "$raw_transcript" --output "$raw_json"; then
      write_status "FAIL" "Optimizer agent output was not valid DAG JSON."
      return 1
    fi
  fi

  if ! python3 "$optimizer_py" verify --tasks-json "$tasks_summary" --raw-json "$raw_json" --output "$verified_json" --waves-txt "$waves_txt"; then
    write_status "FAIL" "Optimizer DAG verification failed."
    return 1
  fi

  if ! create_worktrees "$verified_json" "$worktrees_txt" "$run_label"; then
    write_status "FAIL" "Worktree creation failed. Inspect $worktrees_txt and clean existing branches/paths before retrying."
    return 1
  fi

  if [ "$(json_get_parallelizable "$verified_json")" = "true" ]; then
    write_status "PASS" "Verified DAG contains a parallel wave; worktree setup recorded in $worktrees_txt."
  else
    write_status "PASS" "Verified DAG contains no parallel wave; no worktrees prepared."
  fi
  log "worktree optimization complete: $(head -n1 "$status_file")"
}

run_optimizer
