#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(pwd)"
BERYL_AGENT_DIR="$(dirname "${SCRIPT_DIR}")"
STATUS_FILE="${TARGET_DIR}/.beryl/agent/bootstrap-status.json"
LOG_PATH="${BERYL_AGENT_LOG_PATH:-${TARGET_DIR}/.beryl/agent/bootstrap-runner.log}"
PROMPT_TEMPLATE="${BERYL_AGENT_DIR}/templates/bootstrap/bootstrap-prompt.md"
REQUIRED_TEMPLATE_ROOT="${BERYL_AGENT_DIR}/templates/install"
PROMPT_FILE_PATH=""
cleanup_prompt_file() {
  if [[ -n "${PROMPT_FILE_PATH:-}" ]]; then
    rm -f "${PROMPT_FILE_PATH}"
  fi
}

REQUIRED_FILES=(
  "project-brief.md"
  "architecture.md"
  "design-tree.md"
  "testing-policy.md"
  "ubiquitous-language.md"
  "agent-rules.md"
  "task-routing.md"
)

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

json_escape() {
  local value="$1"
  printf '%s' "${value}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\n/\\n/g' -e 's/\r/\\r/g' -e 's/\t/\\t/g'
}

json_array() {
  local list="$1"
  local first=1
  local item

  printf "["
  while IFS= read -r item; do
    [[ -n "${item}" ]] || continue
    if [[ "${first}" -eq 0 ]]; then
      printf ","
    fi
    first=0
    printf '"%s"' "$(json_escape "${item}")"
  done <<<"${list}"
  printf "]"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

snapshot_files() {
  local -n out_ref="$1"
  local file rel

  while IFS= read -r -d '' file; do
    rel="${file#${TARGET_DIR}/}"
    out_ref["${rel}"]="$(sha256_of "${file}")"
  done < <(find "${TARGET_DIR}" -type f -print0 | sort -z)
}

changed_paths() {
  local -n before_ref="$1"
  local -n after_ref="$2"
  local -n out_ref="$3"
  local path

  out_ref=()

  for path in "${!after_ref[@]}"; do
    if [[ -z "${before_ref[${path}]:-}" ]]; then
      out_ref+=("${path}")
    elif [[ "${before_ref[${path}]}" != "${after_ref[${path}]}" ]]; then
      out_ref+=("${path}")
    fi
  done

  for path in "${!before_ref[@]}"; do
    [[ -n "${after_ref[${path}]:-}" ]] || out_ref+=("${path}")
  done
}

allowed_change_path() {
  local path="$1"
  case "${path}" in
    .beryl/agent/*.md) return 0 ;;
    .beryl/agent/bootstrap-status.json) return 0 ;;
    .beryl/agent/bootstrap-runner.log) return 0 ;;
    *) return 1 ;;
  esac
}

has_template_placeholders() {
  local file="$1"
  grep -Eq '\\[[A-Za-z][A-Za-z0-9 _/.,-]+\\]' "${file}"
}

required_state() {
  local -n missing_ref="$1"
  local -n filled_ref="$2"
  local rel target_file template_file

  missing_ref=()
  filled_ref=()

  for rel in "${REQUIRED_FILES[@]}"; do
    target_file="${TARGET_DIR}/.beryl/agent/${rel}"
    template_file="${REQUIRED_TEMPLATE_ROOT}/${rel}"

    if [[ ! -f "${target_file}" ]]; then
      missing_ref+=("${rel}")
      continue
    fi

    if [[ -f "${template_file}" ]] && cmp -s "${target_file}" "${template_file}"; then
      missing_ref+=("${rel}")
      continue
    fi

    if [[ -f "${template_file}" ]] && has_template_placeholders "${target_file}"; then
      missing_ref+=("${rel}")
      continue
    fi

    filled_ref+=("${rel}")
  done
}

resolve_runner() {
  local request="${BERYL_AGENT_RUNNER:-}"

  case "${request}" in
    "")
      if command -v codex >/dev/null 2>&1; then
        printf "codex\n"
      elif command -v claude >/dev/null 2>&1; then
        printf "claude\n"
      else
        printf "off\n"
      fi
      ;;
    off)
      printf "off\n"
      ;;
    codex|claude|custom)
      printf "%s\n" "${request}"
      ;;
    *)
      fail "BERYL_AGENT_RUNNER must be codex, claude, custom, or off"
      ;;
  esac
}

runner_version() {
  local runner="$1"

  if [[ "${runner}" == "custom" ]]; then
    printf "custom\n"
    return 0
  fi

  if ! command -v "${runner}" >/dev/null 2>&1; then
    printf "not found\n"
    return 0
  fi

  local version
  version="$(${runner} --version 2>/dev/null | head -n 1 || true)"
  if [[ -n "${version}" ]]; then
    printf '%s\n' "${version}"
  else
    printf 'present\n'
  fi
}

validate_custom_template() {
  local template="$1"
  [[ -n "${template}" ]] || fail "BERYL_AGENT_COMMAND_TEMPLATE is required for runner=custom"
  [[ "${template}" == *"{prompt_file}"* ]] || fail "custom template must include {prompt_file}"
  [[ "${template}" == *"{target_dir}"* ]] || fail "custom template must include {target_dir}"
  if (( ${#template} != $(printf '%s' "${template}" | tr -cd 'A-Za-z0-9._=/:{} -' | wc -c) )); then
    fail "custom command template contains unsupported characters"
  fi
}

render_custom_command() {
  local template="$1"
  local prompt_file="$2"
  local target_dir="$3"

  validate_custom_template "${template}"
  template="${template//\{prompt_file\}/${prompt_file}}"
  template="${template//\{target_dir\}/${target_dir}}"
  printf '%s' "${template}"
}

run_runner() {
  local runner="$1"
  local prompt_file="$2"
  local timeout_seconds="${BERYL_AGENT_TIMEOUT_SECONDS:-120}"
  local status=0
  local rendered=""

  if ! [[ "${timeout_seconds}" =~ ^[0-9]+$ ]]; then
    fail "BERYL_AGENT_TIMEOUT_SECONDS must be a positive integer"
  fi

  mkdir -p "$(dirname "${LOG_PATH}")"

  case "${runner}" in
    codex)
      rendered="codex exec {prompt_file}"
      if ! command -v codex >/dev/null 2>&1; then
        fail "codex not found"
      fi
      if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}" codex exec "$(cat "${prompt_file}")" >"${LOG_PATH}" 2>&1 || status=$?
      else
        codex exec "$(cat "${prompt_file}")" >"${LOG_PATH}" 2>&1 || status=$?
      fi
      ;;
    claude)
      rendered="claude -p {prompt_file}"
      if ! command -v claude >/dev/null 2>&1; then
        fail "claude not found"
      fi
      if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}" claude -p "$(cat "${prompt_file}")" >"${LOG_PATH}" 2>&1 || status=$?
      else
        claude -p "$(cat "${prompt_file}")" >"${LOG_PATH}" 2>&1 || status=$?
      fi
      ;;
    custom)
      rendered="$(render_custom_command "${BERYL_AGENT_COMMAND_TEMPLATE}" "${prompt_file}" "${TARGET_DIR}")"
      if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}" bash -lc "${rendered}" >"${LOG_PATH}" 2>&1 || status=$?
      else
        bash -lc "${rendered}" >"${LOG_PATH}" 2>&1 || status=$?
      fi
      ;;
    *)
      fail "unsupported runner: ${runner}"
      ;;
  esac

  printf '%s|%s' "${status}" "${rendered}"
}

status_array() {
  local list=""
  local file
  for file in "$@"; do
    list+="${file}"$'\n'
  done
  json_array "${list}"
}

write_status() {
  local status="$1"
  local missing_json="$2"
  local filled_json="$3"
  local errors_json="$4"
  local command="$5"
  local runner="$6"

  local source_ref="${BERYL_BOOTSTRAP_SOURCE_REF:-unknown}"
  local installer_version="${BERYL_BOOTSTRAP_INSTALLER_VERSION:-1}"
  local profile="${BERYL_BOOTSTRAP_PROFILE:-}"
  local components

  components="${BERYL_BOOTSTRAP_COMPONENTS:-}"
  components="${components//$'\r'/}"

  mkdir -p "${TARGET_DIR}/.beryl/agent"
  {
    printf '{\n'
    printf '  "timestamp": "%s",\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '  "installer_version": "%s",\n' "$(json_escape "${installer_version}")"
    printf '  "source_ref": "%s",\n' "$(json_escape "${source_ref}")"
    printf '  "profile/components": {\n'
    printf '    "profile": "%s",\n' "$(json_escape "${profile}")"
    printf '    "components": %s\n' "$(json_array "${components}")"
    printf '  },\n'
    printf '  "runner": "%s",\n' "$(json_escape "${runner}")"
    printf '  "runner_version": "%s",\n' "$(json_escape "$(runner_version "${runner}")")"
    printf '  "status": "%s",\n' "$(json_escape "${status}")"
    printf '  "missing_files": %s,\n' "${missing_json}"
    printf '  "filled_files": %s,\n' "${filled_json}"
    printf '  "errors": %s,\n' "${errors_json}"
    printf '  "command": "%s"\n' "$(json_escape "${command}")"
    printf '}\n'
  } >"${STATUS_FILE}"
}

build_prompt() {
  local required_block="$1"
  local runner="$2"
  local policy="$3"

  while IFS= read -r line; do
    line="${line//{target_dir}/${TARGET_DIR}}"
    line="${line//{required_files}/${required_block}}"
    line="${line//{runner}/${runner}}"
    line="${line//{policy}/${policy}}"
    line="${line//{status_file}/${STATUS_FILE}}"
    line="${line//{installer_version}/${BERYL_BOOTSTRAP_INSTALLER_VERSION:-1}}"
    line="${line//{source_ref}/${BERYL_BOOTSTRAP_SOURCE_REF:-unknown}}"
    line="${line//{profile}/${BERYL_BOOTSTRAP_PROFILE:-}}"
    printf "%s\n" "${line}"
  done <"${PROMPT_TEMPLATE}"
}

main() {
  local fallback="${BERYL_AGENT_FALLBACK:-on}"
  local policy="${BERYL_AGENT_POLICY:-interactive}"
  local -a pre_missing=() pre_filled=() post_missing=() post_filled=() errors=()
  local -a changed=()
  local -A before_snapshot=() after_snapshot=()
  local status=""
  local runner=""
  local run_output=""
  local run_status=0
  local run_cmd=""
  local prompt_file=""
  local required_block=""

  [[ -f "${PROMPT_TEMPLATE}" ]] || fail "bootstrap prompt template missing: ${PROMPT_TEMPLATE}"

  case "${fallback}" in
    on|off) ;;
    *) fail "--agent-fallback must be on or off" ;;
  esac
  case "${policy}" in
    strict|interactive) ;;
    *) fail "--agent-policy must be strict or interactive" ;;
  esac

  snapshot_files before_snapshot
  required_state pre_missing pre_filled

  if (( ${#pre_missing[@]} == 0 )); then
    status="already-complete"
    write_status "${status}" "$(json_array "")" "$(status_array "${pre_filled[@]}")" "$(json_array "")" "already complete" "off"
    printf "beryl: bootstrap required files are already complete.\n"
    return 0
  fi

  runner="$(resolve_runner)"
  if [[ "${runner}" == "off" ]]; then
    errors+=("No allowed agent runner found.")
    if [[ "${fallback}" == "off" ]]; then
      errors+=("Fallback disabled via --agent-fallback off.")
      status="failed"
    else
      status="manual"
    fi

    run_cmd="BERYL_AGENT_RUNNER=<codex|claude|custom> BERYL_AGENT_COMMAND_TEMPLATE='<target> {prompt_file} {target_dir}'"
    write_status "${status}" "$(status_array "${pre_missing[@]}")" "$(status_array "${pre_filled[@]}")" "$(status_array "${errors[@]}")" "${run_cmd}" "off"
    printf "beryl: bootstrap runner unavailable; see %s for fallback status.\n" "${STATUS_FILE#${TARGET_DIR}/}" >&2
    printf "beryl: bootstrap status: %s\n" "${status}" >&2
    if [[ "${fallback}" == "off" ]]; then
      return 1
    fi
    return 0
  fi

  for file in "${pre_missing[@]}"; do
    required_block+="  - ${file}"$'\n'
  done

  prompt_file="$(mktemp)"
  PROMPT_FILE_PATH="${prompt_file}"
  build_prompt "${required_block}" "${runner}" "${policy}" >"${prompt_file}"
  trap 'cleanup_prompt_file' EXIT

  run_output="$(run_runner "${runner}" "${prompt_file}")"
  run_status="${run_output%|*}"
  run_cmd="${run_output#*|}"

  if [[ "${run_status}" != "0" ]]; then
    status="failed"
    errors+=("bootstrap runner exited with status ${run_status}")
  else
    status="completed"
  fi

  snapshot_files after_snapshot
  changed_paths before_snapshot after_snapshot changed

  if [[ "${policy}" == "strict" ]]; then
    for path in "${changed[@]}"; do
      if ! allowed_change_path "${path}"; then
        status="failed"
        errors+=("strict policy violation: ${path}")
      fi
    done
  fi

  required_state post_missing post_filled
  if [[ "${status}" != "failed" && "${#post_missing[@]}" -gt 0 ]]; then
    status="partial"
    errors+=("one or more required files remain unfilled")
  fi

  write_status "${status}" "$(status_array "${post_missing[@]}")" "$(status_array "${post_filled[@]}")" "$(status_array "${errors[@]}")" "${run_cmd}" "${runner}"

  if [[ "${status}" == "failed" && "${fallback}" == "off" ]]; then
    return 1
  fi

  return 0
}

main "$@"
