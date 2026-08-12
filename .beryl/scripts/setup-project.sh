#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

usage() {
  cat <<'USAGE'
Usage:
  .beryl/scripts/setup-project.sh [OPTIONS] TARGET_DIR

Local onboarding frontend for install.sh. Setup collects project choices, then
delegates exactly one install or locked update transaction to the local Beryl
checkout. It never copies components, writes lockfiles, initializes Git, or
changes core.hooksPath itself.

Options:
  --non-interactive           Never read stdin. TARGET_DIR is required.
                             Defaults for a new target: profile=standard,
                             stack=generic, test-runner=none, no bootstrap,
                             and no deterministic check run.
  --profile minimal|standard|full
                             Select a profile for a new install or explicitly
                             replace a locked target's component selection.
  --components a,b            Select explicit components instead of a profile.
  --root-conflict fail|skip|overwrite
                             Lifecycle policy for existing root contracts.
                             Default for a new target: fail. A locked target
                             reuses its recorded policy unless this is given.
  --stack javascript|python|go|generic
                             Configure the affected-test adapter after the
                             committed lifecycle transaction.
  --test-runner jest|vitest|pytest-testmon|go-test|none|custom
                             Select the adapter for --stack. Default: none.
  --related-test-cmd ARRAY    Bash array syntax for a custom related-test command.
  --full-test-cmd ARRAY       Bash array syntax for a custom full-test command.
  --enable-githooks           Ask the lifecycle engine to activate Beryl's
                             pre-commit hook. Disabled by default.
  --hook-conflict fail|preserve|replace
                             Lifecycle policy for an existing core.hooksPath.
                             Default when enabling: fail.
  --bootstrap                 Run the standalone agent bootstrap after a
                             successful lifecycle transaction.
  --agent-fallback on|off     Bootstrap fallback policy. Default: on.
  --agent-runner codex|claude|custom|off
  --agent-command-template TPL
  --agent-policy strict|interactive
  --run-check                 Run target .beryl/scripts/check.sh after setup.
  --skip-check                Do not run the target check (the non-interactive
                             default).
  -h, --help                  Show this help.

For a target with .beryl/lock.json, setup delegates --update and preserves the
locked component selection unless --profile or --components is explicit. Hook
activation remains opt-in through install.sh's explicit --enable-githooks
interface; setup only reports whether Git (including linked worktrees) exists
and forwards the selected hook policy without mutating Git itself.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

prompt() {
  local label="$1"
  local default="${2:-}"
  local value

  if [[ -n "${default}" ]]; then
    printf '%s [%s]: ' "${label}" "${default}" >&2
  else
    printf '%s: ' "${label}" >&2
  fi
  IFS= read -r value || fail "input ended while reading: ${label}"
  printf '%s' "${value:-${default}}"
}

choose() {
  local label="$1"
  shift
  local -a options=("$@")
  local choice index

  printf '\n%s\n' "${label}" >&2
  for index in "${!options[@]}"; do
    printf '  %s) %s\n' "$((index + 1))" "${options[$index]}" >&2
  done
  while true; do
    printf 'Choose 1-%s: ' "${#options[@]}" >&2
    IFS= read -r choice || fail "input ended while choosing: ${label}"
    if [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
      printf '%s' "${options[$((choice - 1))]}"
      return 0
    fi
    printf 'Please choose a listed option.\n' >&2
  done
}

confirm() {
  local label="$1"
  local default="${2:-n}"
  local value suffix

  case "${default}" in
    y|Y) suffix='Y/n' ;;
    n|N) suffix='y/N' ;;
    *) fail 'confirm default must be y or n' ;;
  esac
  while true; do
    printf '%s [%s]: ' "${label}" "${suffix}" >&2
    IFS= read -r value || fail "input ended while reading: ${label}"
    value="${value:-${default}}"
    case "${value}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf 'Please answer y or n.\n' >&2 ;;
    esac
  done
}

configure_affected_tests() {
  local config="${TARGET_DIR}/.beryl/agent/affected-tests.conf"
  local related_cmd='()'
  local full_cmd='()'
  local tmp

  [[ "${TEST_RUNNER}" != 'none' ]] || return 0
  [[ -f "${config}" ]] || {
    printf 'setup-project: affected-test adapter is unavailable; skipped configuration\n' >&2
    return 0
  }
  [[ ! -L "${config}" ]] || {
    printf 'setup-project: refusing to configure a symlinked affected-test adapter\n' >&2
    return 1
  }

  case "${TEST_RUNNER}" in
    jest)
      related_cmd='(npx --no-install jest --findRelatedTests --passWithNoTests)'
      full_cmd='(npm test)'
      ;;
    vitest)
      related_cmd='(npx --no-install vitest related --run)'
      full_cmd='(npm test)'
      ;;
    pytest-testmon)
      related_cmd='(pytest --testmon)'
      full_cmd='(pytest)'
      ;;
    go-test)
      full_cmd='(go test ./...)'
      ;;
    custom)
      related_cmd="${RELATED_TEST_CMD}"
      full_cmd="${FULL_TEST_CMD}"
      ;;
    *) fail "unsupported test runner: ${TEST_RUNNER}" ;;
  esac

  ADAPTER_CONFIG_BACKUP="$(mktemp "${config}.backup.XXXXXX")" || return 1
  if ! cp -p "${config}" "${ADAPTER_CONFIG_BACKUP}"; then
    rm -f "${ADAPTER_CONFIG_BACKUP}"
    ADAPTER_CONFIG_BACKUP=''
    return 1
  fi
  tmp="$(mktemp "${config}.staged.XXXXXX")" || {
    rm -f "${ADAPTER_CONFIG_BACKUP}"
    ADAPTER_CONFIG_BACKUP=''
    return 1
  }
  awk -v related="${related_cmd}" -v full="${full_cmd}" '
    /^FULL_TEST_CMD=/ { print "FULL_TEST_CMD=" full; next }
    /^RELATED_TEST_CMD=/ { print "RELATED_TEST_CMD=" related; next }
    { print }
  ' "${config}" >"${tmp}" || {
    rm -f "${tmp}" "${ADAPTER_CONFIG_BACKUP}"
    ADAPTER_CONFIG_BACKUP=''
    return 1
  }
  if ! mv "${tmp}" "${config}"; then
    rm -f "${tmp}"
    rm -f "${ADAPTER_CONFIG_BACKUP}"
    ADAPTER_CONFIG_BACKUP=''
    return 1
  fi
  ADAPTER_CONFIG_CHANGED=1
  printf 'setup-project: configured affected tests for %s / %s\n' "${STACK}" "${TEST_RUNNER}"
}

rollback_affected_tests_configuration() {
  [[ "${ADAPTER_CONFIG_CHANGED:-0}" == '1' ]] || return 0
  [[ -n "${ADAPTER_CONFIG_BACKUP:-}" && -f "${ADAPTER_CONFIG_BACKUP}" ]] || return 1
  mv "${ADAPTER_CONFIG_BACKUP}" "${TARGET_DIR}/.beryl/agent/affected-tests.conf" || return 1
  ADAPTER_CONFIG_BACKUP=''
  ADAPTER_CONFIG_CHANGED=0
  printf 'setup-project: restored affected-test adapter after follow-up failure\n' >&2
}

discard_affected_tests_backup() {
  [[ -n "${ADAPTER_CONFIG_BACKUP:-}" ]] && rm -f "${ADAPTER_CONFIG_BACKUP}"
  ADAPTER_CONFIG_BACKUP=''
  ADAPTER_CONFIG_CHANGED=0
}

report_git_state() {
  command -v git >/dev/null 2>&1 || {
    printf 'setup-project: git not found on PATH; hook activation remains unavailable\n'
    return 0
  }
  if git -C "${TARGET_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'setup-project: Git repository detected (including linked worktrees); hook activation was not changed\n'
  else
    printf 'setup-project: target is not a Git repository; hook activation was not changed\n'
  fi
}

run_bootstrap() {
  local -a bootstrap=(sh "${REPO_ROOT}/install.sh" --bootstrap-agent --target "${TARGET_DIR}" \
    --agent-fallback "${AGENT_FALLBACK}" --agent-policy "${AGENT_POLICY}")
  [[ -n "${AGENT_RUNNER}" ]] && bootstrap+=(--agent-runner "${AGENT_RUNNER}")
  [[ -n "${AGENT_COMMAND_TEMPLATE}" ]] && bootstrap+=(--agent-command-template "${AGENT_COMMAND_TEMPLATE}")

  if "${bootstrap[@]}"; then
    printf 'setup-project: standalone bootstrap complete\n'
  else
    bootstrap_status=$?
    printf 'setup-project: lifecycle is committed; standalone bootstrap failed exit=%s\n' "${bootstrap_status}" >&2
    return "${bootstrap_status}"
  fi
}

run_target_check() {
  local check_path="${TARGET_DIR}/.beryl/scripts/check.sh"
  [[ -x "${check_path}" ]] || {
    printf 'setup-project: target check is unavailable; skipped\n'
    return 0
  }
  if (cd "${TARGET_DIR}" && "${check_path}"); then
    printf 'setup-project: deterministic check passed\n'
    return 0
  fi
  printf 'setup-project: lifecycle is committed; deterministic check failed\n' >&2
  return 1
}

select_interactive_components() {
  local choice
  choice="$(choose 'Choose the Beryl component set' \
    'standard' 'minimal' 'full' 'custom components')"
  case "${choice}" in
    standard|minimal|full)
      PROFILE="${choice}"
      PROFILE_EXPLICIT=1
      COMPONENTS_CSV=''
      COMPONENTS_EXPLICIT=0
      ;;
    'custom components')
      COMPONENTS_CSV="$(prompt 'Components to install' 'agent-core,checks')"
      COMPONENTS_EXPLICIT=1
      PROFILE=''
      PROFILE_EXPLICIT=0
      ;;
  esac
}

select_interactive_root_policy() {
  ROOT_CONFLICT="$(choose 'Choose how to handle existing root contracts' \
    'fail' 'skip' 'overwrite')"
}

select_interactive_hook_policy() {
  if ((ENABLE_GITHOOKS == 0)) && confirm 'Enable Beryl pre-commit hooks through the lifecycle engine?' 'n'; then
    ENABLE_GITHOOKS=1
  fi
  if ((ENABLE_GITHOOKS == 1)) && ((HOOK_CONFLICT_EXPLICIT == 0)); then
    HOOK_CONFLICT="$(choose 'Choose how to handle an existing Git hook manager' \
      'fail' 'preserve' 'replace')"
  fi
}

select_interactive_locked_lifecycle_choices() {
  if ((PROFILE_EXPLICIT == 0)) && ((COMPONENTS_EXPLICIT == 0)) && \
     ! confirm 'Reuse the locked Beryl component selection?' 'y'; then
    select_interactive_components
  fi
  if ((ROOT_CONFLICT_EXPLICIT == 0)) && \
     ! confirm 'Reuse the locked root-contract conflict policy?' 'y'; then
    select_interactive_root_policy
    ROOT_CONFLICT_EXPLICIT=1
  fi
}

select_interactive_configuration() {
  local stack_choice runner_choice
  if ((STACK_EXPLICIT == 0)); then
    stack_choice="$(choose 'Choose the closest project stack' \
      'JavaScript/TypeScript' 'Python' 'Go' 'Generic shell/custom')"
    case "${stack_choice}" in
      'JavaScript/TypeScript') STACK='javascript' ;;
      Python) STACK='python' ;;
      Go) STACK='go' ;;
      *) STACK='generic' ;;
    esac
  fi

  ((TEST_RUNNER_EXPLICIT == 0)) || {
    if [[ "${TEST_RUNNER}" == 'custom' ]]; then
      ((RELATED_TEST_CMD_EXPLICIT == 1)) || RELATED_TEST_CMD="$(prompt 'RELATED_TEST_CMD' '()')"
      ((FULL_TEST_CMD_EXPLICIT == 1)) || FULL_TEST_CMD="$(prompt 'FULL_TEST_CMD' '()')"
    fi
    return 0
  }

  case "${STACK}" in
    javascript)
      runner_choice="$(choose 'Choose the test runner' 'Jest' 'Vitest' 'No configuration')"
      case "${runner_choice}" in Jest) TEST_RUNNER='jest' ;; Vitest) TEST_RUNNER='vitest' ;; *) TEST_RUNNER='none' ;; esac
      ;;
    python)
      runner_choice="$(choose 'Choose the test runner' 'pytest + testmon' 'No configuration')"
      [[ "${runner_choice}" == 'pytest + testmon' ]] && TEST_RUNNER='pytest-testmon' || TEST_RUNNER='none'
      ;;
    go)
      runner_choice="$(choose 'Choose the test runner' 'go test' 'No configuration')"
      [[ "${runner_choice}" == 'go test' ]] && TEST_RUNNER='go-test' || TEST_RUNNER='none'
      ;;
    *)
      STACK='generic'
      runner_choice="$(choose 'Choose the test runner' 'Custom command' 'No configuration')"
      if [[ "${runner_choice}" == 'Custom command' ]]; then
        TEST_RUNNER='custom'
        RELATED_TEST_CMD="$(prompt 'RELATED_TEST_CMD' '()')"
        FULL_TEST_CMD="$(prompt 'FULL_TEST_CMD' '()')"
      else
        TEST_RUNNER='none'
      fi
      ;;
  esac
}

select_interactive_bootstrap() {
  if ((BOOTSTRAP_AGENT == 0)) && confirm 'Run a coding agent bootstrap for project context now?' 'n'; then
    BOOTSTRAP_AGENT=1
  fi
  ((BOOTSTRAP_AGENT == 1)) || return 0
  if [[ "${AGENT_FALLBACK_EXPLICIT}" == '0' ]]; then
    AGENT_FALLBACK="$(choose 'Use a fallback when the requested agent runner is unavailable' 'on' 'off')"
  fi
  if [[ "${AGENT_RUNNER_EXPLICIT}" == '0' ]]; then
    AGENT_RUNNER="$(choose 'Choose an agent runner' 'codex' 'claude' 'custom' 'off')"
  fi
  if [[ "${AGENT_RUNNER}" == 'custom' && "${AGENT_COMMAND_TEMPLATE_EXPLICIT}" == '0' ]]; then
    AGENT_COMMAND_TEMPLATE="$(prompt 'Agent command template')"
  fi
  if [[ "${AGENT_POLICY_EXPLICIT}" == '0' ]]; then
    AGENT_POLICY="$(choose 'Choose the bootstrap agent policy' 'strict' 'interactive')"
  fi
}

select_interactive_check_mode() {
  [[ "${CHECK_MODE}" == 'auto' ]] || return 0
  if confirm 'Run ./.beryl/scripts/check.sh in the target now?' 'y'; then
    CHECK_MODE='run'
  else
    CHECK_MODE='skip'
  fi
}

validate_setup_choices() {
  ((PROFILE_EXPLICIT == 0 || COMPONENTS_EXPLICIT == 0)) || fail 'use --profile or --components, not both'
  case "${PROFILE}" in ''|minimal|standard|full) ;; *) fail '--profile must be minimal, standard, or full' ;; esac
  [[ -z "${COMPONENTS_CSV}" || "${COMPONENTS_CSV}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*(,[A-Za-z0-9][A-Za-z0-9-]*)*$ ]] || \
    fail '--components must be a comma-separated component list'
  case "${AGENT_FALLBACK}" in on|off) ;; *) fail '--agent-fallback must be on or off' ;; esac
  case "${AGENT_POLICY}" in strict|interactive) ;; *) fail '--agent-policy must be strict or interactive' ;; esac
  case "${AGENT_RUNNER}" in ''|codex|claude|custom|off) ;; *) fail '--agent-runner must be codex, claude, custom, or off' ;; esac
  case "${STACK}" in javascript|python|go|generic) ;; *) fail '--stack must be javascript, python, go, or generic' ;; esac
  case "${TEST_RUNNER}" in jest|vitest|pytest-testmon|go-test|none|custom) ;; *) fail '--test-runner is invalid' ;; esac
  case "${ROOT_CONFLICT}" in fail|skip|overwrite) ;; *) fail '--root-conflict must be fail, skip, or overwrite' ;; esac
  case "${HOOK_CONFLICT}" in fail|preserve|replace) ;; *) fail '--hook-conflict must be fail, preserve, or replace' ;; esac
  [[ "${TEST_RUNNER}" != custom || ( -n "${RELATED_TEST_CMD}" && -n "${FULL_TEST_CMD}" ) ]] || fail 'custom test runner requires test commands'
  [[ "${AGENT_RUNNER}" != custom || -n "${AGENT_COMMAND_TEMPLATE}" ]] || fail 'custom agent runner requires --agent-command-template'
  if [[ -n "${COMPONENTS_CSV}" ]]; then
    local component
    local -a components=()
    IFS=',' read -r -a components <<<"${COMPONENTS_CSV}"
    for component in "${components[@]}"; do
      grep -Fq "\"name\":\"${component}\"" "${REPO_ROOT}/.beryl/beryl.components.json" || \
        fail "unknown component in --components: ${component}"
    done
  fi
  if [[ "${TEST_RUNNER}" == 'custom' ]]; then
    validate_command_array "${RELATED_TEST_CMD}" 'RELATED_TEST_CMD'
    validate_command_array "${FULL_TEST_CMD}" 'FULL_TEST_CMD'
  fi
  if [[ "${TEST_RUNNER}" != 'none' && -L "${TARGET_DIR}/.beryl/agent/affected-tests.conf" ]]; then
    fail 'refusing to configure a symlinked affected-test adapter'
  fi
}

validate_command_array() {
  local command_array="$1"
  local label="$2"
  local config
  config="$(mktemp "${TMPDIR:-/tmp}/beryl-setup-command.XXXXXX")" || fail "could not stage ${label} validation"
  printf '%s=%s\n' "${label}" "${command_array}" >"${config}"
  if ! bash -c 'source "$1"; sc_load_conf "$2" "$3"' bash \
    "${REPO_ROOT}/.beryl/scripts/safe-conf.sh" "${config}" "${label}"; then
    rm -f "${config}"
    fail "${label} must use the safe command-array syntax documented in affected-tests.conf"
  fi
  rm -f "${config}"
}

main() {
  local arg target_locked=0 lifecycle_status=0 post_status=0
  local -a lifecycle

  PROFILE=''
  COMPONENTS_CSV=''
  PROFILE_EXPLICIT=0
  COMPONENTS_EXPLICIT=0
  ROOT_CONFLICT='fail'
  ROOT_CONFLICT_EXPLICIT=0
  STACK_EXPLICIT=0
  TEST_RUNNER_EXPLICIT=0
  RELATED_TEST_CMD_EXPLICIT=0
  FULL_TEST_CMD_EXPLICIT=0
  NON_INTERACTIVE=0
  BOOTSTRAP_AGENT=0
  ENABLE_GITHOOKS=0
  HOOK_CONFLICT='fail'
  HOOK_CONFLICT_EXPLICIT=0
  CHECK_MODE='auto'
  STACK='generic'
  TEST_RUNNER='none'
  RELATED_TEST_CMD='()'
  FULL_TEST_CMD='()'
  TARGET_DIR=''
  AGENT_FALLBACK="${BERYL_AGENT_FALLBACK:-on}"
  AGENT_RUNNER="${BERYL_AGENT_RUNNER:-}"
  AGENT_COMMAND_TEMPLATE="${BERYL_AGENT_COMMAND_TEMPLATE:-}"
  AGENT_POLICY="${BERYL_AGENT_POLICY:-interactive}"
  AGENT_FALLBACK_EXPLICIT=0
  AGENT_RUNNER_EXPLICIT=0
  AGENT_COMMAND_TEMPLATE_EXPLICIT=0
  AGENT_POLICY_EXPLICIT=0
  ADAPTER_CONFIG_BACKUP=''
  ADAPTER_CONFIG_CHANGED=0

  while (($# > 0)); do
    arg="$1"
    case "${arg}" in
      -h|--help) usage; return 0 ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --profile) [[ $# -ge 2 ]] || fail '--profile requires a value'; PROFILE="$2"; PROFILE_EXPLICIT=1; shift 2 ;;
      --profile=*) PROFILE="${arg#--profile=}"; PROFILE_EXPLICIT=1; shift ;;
      --components) [[ $# -ge 2 ]] || fail '--components requires a value'; COMPONENTS_CSV="$2"; COMPONENTS_EXPLICIT=1; shift 2 ;;
      --components=*) COMPONENTS_CSV="${arg#--components=}"; COMPONENTS_EXPLICIT=1; shift ;;
      --root-conflict) [[ $# -ge 2 ]] || fail '--root-conflict requires a value'; ROOT_CONFLICT="$2"; ROOT_CONFLICT_EXPLICIT=1; shift 2 ;;
      --root-conflict=*) ROOT_CONFLICT="${arg#--root-conflict=}"; ROOT_CONFLICT_EXPLICIT=1; shift ;;
      --stack) [[ $# -ge 2 ]] || fail '--stack requires a value'; STACK="$2"; STACK_EXPLICIT=1; shift 2 ;;
      --stack=*) STACK="${arg#--stack=}"; STACK_EXPLICIT=1; shift ;;
      --test-runner) [[ $# -ge 2 ]] || fail '--test-runner requires a value'; TEST_RUNNER="$2"; TEST_RUNNER_EXPLICIT=1; shift 2 ;;
      --test-runner=*) TEST_RUNNER="${arg#--test-runner=}"; TEST_RUNNER_EXPLICIT=1; shift ;;
      --related-test-cmd) [[ $# -ge 2 ]] || fail '--related-test-cmd requires a value'; RELATED_TEST_CMD="$2"; RELATED_TEST_CMD_EXPLICIT=1; shift 2 ;;
      --related-test-cmd=*) RELATED_TEST_CMD="${arg#--related-test-cmd=}"; RELATED_TEST_CMD_EXPLICIT=1; shift ;;
      --full-test-cmd) [[ $# -ge 2 ]] || fail '--full-test-cmd requires a value'; FULL_TEST_CMD="$2"; FULL_TEST_CMD_EXPLICIT=1; shift 2 ;;
      --full-test-cmd=*) FULL_TEST_CMD="${arg#--full-test-cmd=}"; FULL_TEST_CMD_EXPLICIT=1; shift ;;
      --enable-githooks) ENABLE_GITHOOKS=1; shift ;;
      --hook-conflict) [[ $# -ge 2 ]] || fail '--hook-conflict requires a value'; HOOK_CONFLICT="$2"; HOOK_CONFLICT_EXPLICIT=1; shift 2 ;;
      --hook-conflict=*) HOOK_CONFLICT="${arg#--hook-conflict=}"; HOOK_CONFLICT_EXPLICIT=1; shift ;;
      --bootstrap) BOOTSTRAP_AGENT=1; shift ;;
      --agent-fallback) [[ $# -ge 2 ]] || fail '--agent-fallback requires a value'; AGENT_FALLBACK="$2"; AGENT_FALLBACK_EXPLICIT=1; shift 2 ;;
      --agent-fallback=*) AGENT_FALLBACK="${arg#--agent-fallback=}"; AGENT_FALLBACK_EXPLICIT=1; shift ;;
      --agent-runner) [[ $# -ge 2 ]] || fail '--agent-runner requires a value'; AGENT_RUNNER="$2"; AGENT_RUNNER_EXPLICIT=1; shift 2 ;;
      --agent-runner=*) AGENT_RUNNER="${arg#--agent-runner=}"; AGENT_RUNNER_EXPLICIT=1; shift ;;
      --agent-command-template) [[ $# -ge 2 ]] || fail '--agent-command-template requires a value'; AGENT_COMMAND_TEMPLATE="$2"; AGENT_COMMAND_TEMPLATE_EXPLICIT=1; shift 2 ;;
      --agent-command-template=*) AGENT_COMMAND_TEMPLATE="${arg#--agent-command-template=}"; AGENT_COMMAND_TEMPLATE_EXPLICIT=1; shift ;;
      --agent-policy) [[ $# -ge 2 ]] || fail '--agent-policy requires a value'; AGENT_POLICY="$2"; AGENT_POLICY_EXPLICIT=1; shift 2 ;;
      --agent-policy=*) AGENT_POLICY="${arg#--agent-policy=}"; AGENT_POLICY_EXPLICIT=1; shift ;;
      --run-check) CHECK_MODE='run'; shift ;;
      --skip-check) CHECK_MODE='skip'; shift ;;
      --*) fail "unknown argument: ${arg}" ;;
      *) [[ -z "${TARGET_DIR}" ]] || fail 'only one TARGET_DIR is supported'; TARGET_DIR="${arg}"; shift ;;
    esac
  done

  if [[ -z "${TARGET_DIR}" ]]; then
    ((NON_INTERACTIVE == 0)) || fail '--non-interactive requires TARGET_DIR'
    TARGET_DIR="$(prompt 'Project directory')"
  fi
  case "${TARGET_DIR}" in /*) ;; *) TARGET_DIR="${PWD}/${TARGET_DIR}" ;; esac
  TARGET_DIR="${TARGET_DIR%/}"

  [[ -f "${REPO_ROOT}/install.sh" ]] || fail "local lifecycle engine is unavailable: ${REPO_ROOT}/install.sh"
  INSTALLER_COMMAND=(sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}")

  if [[ -f "${TARGET_DIR}/.beryl/lock.json" ]]; then
    target_locked=1
  fi
  if ((NON_INTERACTIVE == 0)) && ((target_locked == 0)) && ((PROFILE_EXPLICIT == 0)) && ((COMPONENTS_EXPLICIT == 0)); then
    select_interactive_components
  fi
  if ((NON_INTERACTIVE == 1)) && ((target_locked == 0)) && ((PROFILE_EXPLICIT == 0)) && ((COMPONENTS_EXPLICIT == 0)); then
    PROFILE='standard'
  fi
  if ((NON_INTERACTIVE == 0)); then
    if ((target_locked == 1)); then
      select_interactive_locked_lifecycle_choices
    elif ((ROOT_CONFLICT_EXPLICIT == 0)); then
      select_interactive_root_policy
    fi
    select_interactive_hook_policy
    select_interactive_configuration
    select_interactive_bootstrap
    select_interactive_check_mode
  fi
  validate_setup_choices

  lifecycle=("${INSTALLER_COMMAND[@]}" --target "${TARGET_DIR}")
  if ((target_locked == 1)); then
    lifecycle+=(--update)
    printf 'setup-project: delegating locked target update\n'
  else
    printf 'setup-project: delegating new target installation\n'
  fi
  if ((PROFILE_EXPLICIT == 1)) || { ((target_locked == 0)) && [[ -n "${PROFILE}" ]]; }; then
    lifecycle+=(--profile "${PROFILE}")
  fi
  if ((COMPONENTS_EXPLICIT == 1)); then
    lifecycle+=(--components "${COMPONENTS_CSV}")
  fi
  if ((target_locked == 0 || ROOT_CONFLICT_EXPLICIT == 1)); then
    lifecycle+=(--root-conflict "${ROOT_CONFLICT}")
  fi
  if ((ENABLE_GITHOOKS == 1)); then
    lifecycle+=(--enable-githooks)
  fi
  if ((HOOK_CONFLICT_EXPLICIT == 1)); then
    lifecycle+=(--hook-conflict "${HOOK_CONFLICT}")
  fi

  if "${lifecycle[@]}"; then
    :
  else
    lifecycle_status=$?
    printf 'setup-project: lifecycle transaction failed before setup configuration\n' >&2
    return "${lifecycle_status}"
  fi
  printf 'setup-project: lifecycle transaction committed\n'

  if ! configure_affected_tests; then
    printf 'setup-project: affected-test configuration failed after lifecycle commit\n' >&2
    rollback_affected_tests_configuration || true
    return 2
  fi
  report_git_state

  if ((BOOTSTRAP_AGENT == 1)); then
    run_bootstrap || post_status=2
  fi
  if [[ "${CHECK_MODE}" == 'run' ]]; then
    if ! run_target_check; then
      if ! rollback_affected_tests_configuration; then
        printf 'setup-project: could not restore affected-test adapter after check failure\n' >&2
        return 1
      fi
      post_status=2
    fi
  fi

  if ((post_status != 0)) && ! rollback_affected_tests_configuration; then
    printf 'setup-project: could not restore affected-test adapter after follow-up failure\n' >&2
    return 1
  fi
  discard_affected_tests_backup

  if ((post_status != 0)); then
    printf 'setup-project: setup follow-up failed, but the lifecycle remains committed at %s\n' "${TARGET_DIR}" >&2
    return "${post_status}"
  fi
  printf 'Setup complete for %s\n' "${TARGET_DIR}"
}

main "$@"
