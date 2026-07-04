#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"
# shellcheck source=beryl-components.sh
source "${SCRIPT_DIR}/beryl-components.sh"
MANIFEST_PATH="${BERYL_ROOT}/beryl.components.json"

usage() {
  cat <<'USAGE'
Usage:
  .beryl/scripts/setup-project.sh [--profile minimal|standard|full] [--components a,b] [TARGET_DIR]

Interactively installs selected Beryl components into TARGET_DIR, configures the
affected-test gate, optionally enables the Git hook, and can hand off unusual
setup work to a headless coding agent.

If TARGET_DIR is omitted, the script prompts for it.
USAGE
}

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

prompt() {
  local label="$1"
  local default="${2:-}"
  local value

  if [[ -n "${default}" ]]; then
    printf "%s [%s]: " "${label}" "${default}" >&2
    read -r value || fail "input ended while reading: ${label}"
    printf "%s" "${value:-${default}}"
  else
    printf "%s: " "${label}" >&2
    read -r value || fail "input ended while reading: ${label}"
    printf "%s" "${value}"
  fi
}

confirm() {
  local label="$1"
  local default="${2:-y}"
  local value suffix

  case "${default}" in
    y|Y) suffix="Y/n" ;;
    n|N) suffix="y/N" ;;
    *) fail "confirm default must be y or n" ;;
  esac

  while true; do
    printf "%s [%s]: " "${label}" "${suffix}" >&2
    read -r value || fail "input ended while reading: ${label}"
    value="${value:-${default}}"
    case "${value}" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf "Please answer y or n.\n" >&2 ;;
    esac
  done
}

choose() {
  local label="$1"
  shift
  local options=("$@")
  local choice

  printf "\n%s\n" "${label}" >&2
  local i
  for i in "${!options[@]}"; do
    printf "  %s) %s\n" "$((i + 1))" "${options[$i]}" >&2
  done

  while true; do
    printf "Choose 1-%s: " "${#options[@]}" >&2
    read -r choice || fail "input ended while choosing: ${label}"
    if [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
      printf "%s" "${options[$((choice - 1))]}"
      return 0
    fi
    printf "Please choose a listed option.\n" >&2
  done
}

ensure_target_dir() {
  local target="$1"

  [[ -n "${target}" ]] || fail "target directory is required"

  if [[ -e "${target}" && ! -d "${target}" ]]; then
    fail "target exists but is not a directory: ${target}"
  fi

  if [[ ! -d "${target}" ]]; then
    if confirm "Create target directory ${target}?" "y"; then
      mkdir -p "${target}"
    else
      fail "target directory does not exist: ${target}"
    fi
  fi
}

copy_path() {
  local rel="$1"
  local src="${REPO_ROOT}/${rel}"
  local dst="${TARGET_DIR}/${rel}"

  [[ -e "${src}" ]] || return 0
  [[ "${TARGET_DIR}" != "${REPO_ROOT}" ]] || {
    printf "setup-project: target is this repository; kept existing %s\n" "${rel}"
    return 0
  }

  if [[ -e "${dst}" ]]; then
    if ! confirm "Replace existing ${rel} in target?" "n"; then
      printf "setup-project: kept existing %s\n" "${rel}"
      return 0
    fi
  fi

  rm -rf "${dst}"
  mkdir -p "$(dirname "${dst}")"
  cp -R "${src}" "${dst}"
  printf "setup-project: copied %s\n" "${rel}"
}

ensure_gitignore_entry() {
  local gitignore="${TARGET_DIR}/.gitignore"

  touch "${gitignore}"
  if ! grep -qxF ".beryl/agent/session-state.md" "${gitignore}"; then
    printf "\n.beryl/agent/session-state.md\n" >>"${gitignore}"
    printf "setup-project: updated .gitignore\n"
  fi
}

ensure_git_repo() {
  command -v git >/dev/null 2>&1 || {
    printf "setup-project: git not found on PATH; skipped Git repository setup\n"
    return 0
  }

  if git -C "${TARGET_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  if confirm "Target is not a Git repository. Initialize Git there?" "y"; then
    git -C "${TARGET_DIR}" init
    printf "setup-project: initialized Git repository\n"
  fi
}

configure_affected_tests() {
  local stack="$1"
  local runner="$2"
  local config="${TARGET_DIR}/.beryl/agent/affected-tests.conf"
  local related_cmd="()"
  local full_cmd="()"

  [[ -f "${config}" ]] || return 0

  case "${runner}" in
    "Jest")
      related_cmd="(bash -lc 'if [[ -f package.json ]]; then npx --no-install jest --findRelatedTests --passWithNoTests \"\$@\"; else echo \"check-affected: package.json missing; skipping Jest\"; fi' bash)"
      full_cmd="(bash -lc 'if [[ -f package.json ]]; then npm test; else echo \"check-affected: package.json missing; skipping npm test\"; fi')"
      ;;
    "Vitest")
      related_cmd="(bash -lc 'if [[ -f package.json ]]; then npx --no-install vitest related --run \"\$@\"; else echo \"check-affected: package.json missing; skipping Vitest\"; fi' bash)"
      full_cmd="(bash -lc 'if [[ -f package.json ]]; then npm test; else echo \"check-affected: package.json missing; skipping npm test\"; fi')"
      ;;
    "pytest + testmon")
      related_cmd="(bash -lc 'if command -v pytest >/dev/null 2>&1; then pytest --testmon; else echo \"check-affected: pytest missing; skipping pytest-testmon\"; fi')"
      full_cmd="(bash -lc 'if command -v pytest >/dev/null 2>&1; then pytest; else echo \"check-affected: pytest missing; skipping pytest\"; fi')"
      ;;
    "go test")
      related_cmd="()"
      full_cmd="(bash -lc 'if [[ -f go.mod ]]; then go test ./...; else echo \"check-affected: go.mod missing; skipping go test\"; fi')"
      ;;
    "Custom command")
      printf "\nEnter Bash array syntax for custom commands.\n"
      printf "Example: (npm test -- --changed)\n"
      related_cmd="$(prompt "RELATED_TEST_CMD" "()")"
      full_cmd="$(prompt "FULL_TEST_CMD" "()")"
      ;;
    *)
      case "${stack}" in
        "Generic shell/custom")
          related_cmd="()"
          full_cmd="$(prompt "FULL_TEST_CMD" "()")"
          ;;
      esac
      ;;
  esac

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN
  awk -v related="${related_cmd}" -v full="${full_cmd}" '
    /^FULL_TEST_CMD=/ {
      print "FULL_TEST_CMD=" full
      next
    }
    /^RELATED_TEST_CMD=/ {
      print "RELATED_TEST_CMD=" related
      next
    }
    { print }
  ' "${config}" >"${tmp}"
  mv "${tmp}" "${config}"
  printf "setup-project: configured affected tests for %s / %s\n" "${stack}" "${runner}"
}

run_if_present() {
  local description="$1"
  shift

  if [[ -x "$1" ]]; then
    printf "setup-project: %s\n" "${description}"
    (cd "${TARGET_DIR}" && "$@")
  else
    printf "setup-project: skipped %s; missing %s\n" "${description}" "$1"
  fi
}

run_with_optional_env() {
  local description="$1"
  local env_name="$2"
  local env_value="$3"
  local command_path="$4"
  shift 4

  if [[ -x "${command_path}" ]]; then
    printf "setup-project: %s\n" "${description}"
    (cd "${TARGET_DIR}" && env "${env_name}=${env_value}" "${command_path}" "$@")
  else
    printf "setup-project: skipped %s; missing %s\n" "${description}" "${command_path}"
  fi
}

read_multiline_prompt() {
  local prompt_file="$1"

  printf "\nDescribe the project setup you want the coding agent to complete.\n"
  printf "Finish with a line containing only EOF.\n\n"
  : >"${prompt_file}"

  local line
  while IFS= read -r line; do
    [[ "${line}" == "EOF" ]] && break
    printf "%s\n" "${line}" >>"${prompt_file}"
  done
}

run_agent_fallback() {
  local reason="$1"
  local agent_choice command_template prompt_file prompt_text

  printf "\nAI fallback selected: %s\n" "${reason}"
  agent_choice="$(choose "Choose a headless coding agent" \
    "Codex" \
    "Claude" \
    "Custom headless command" \
    "Skip AI fallback")"

  [[ "${agent_choice}" != "Skip AI fallback" ]] || return 0

  prompt_file="$(mktemp)"
  trap 'rm -f "${prompt_file}"' RETURN
  read_multiline_prompt "${prompt_file}"
  prompt_text="$(cat "${prompt_file}")"

  case "${agent_choice}" in
    "Codex")
      if command -v codex >/dev/null 2>&1; then
        if ! (cd "${TARGET_DIR}" && codex exec "${prompt_text}"); then
          printf "setup-project: codex command failed. Try manually:\n"
          printf "  cd %q && codex exec %q\n" "${TARGET_DIR}" "${prompt_text}"
        fi
      else
        printf "setup-project: codex not found on PATH.\n"
        printf "Manual command:\n  cd %q && codex exec %q\n" "${TARGET_DIR}" "${prompt_text}"
      fi
      ;;
    "Claude")
      if command -v claude >/dev/null 2>&1; then
        if ! (cd "${TARGET_DIR}" && claude -p "${prompt_text}"); then
          printf "setup-project: claude command failed. Try manually:\n"
          printf "  cd %q && claude -p %q\n" "${TARGET_DIR}" "${prompt_text}"
        fi
      else
        printf "setup-project: claude not found on PATH.\n"
        printf "Manual command:\n  cd %q && claude -p %q\n" "${TARGET_DIR}" "${prompt_text}"
      fi
      ;;
    "Custom headless command")
      printf "Use placeholders {target_dir}, {prompt_file}, and {prompt_text}.\n"
      command_template="$(prompt "Command template")"
      [[ -n "${command_template}" ]] || fail "custom command template cannot be empty"
      command_template="${command_template//\{target_dir\}/${TARGET_DIR}}"
      command_template="${command_template//\{prompt_file\}/${prompt_file}}"
      command_template="${command_template//\{prompt_text\}/${prompt_text}}"
      bash -lc "${command_template}"
      ;;
  esac
}

split_csv() {
  local csv="$1"
  printf "%s\n" "${csv}" | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d'
}

select_components_interactive() {
  local profile

  profile="$(choose "Choose the Beryl install profile" \
    "standard" \
    "minimal" \
    "full")"
  bc_profile_components "${MANIFEST_PATH}" "${profile}"
}

selected_components() {
  if [[ -n "${COMPONENTS_CSV:-}" ]]; then
    split_csv "${COMPONENTS_CSV}"
  elif [[ -n "${PROFILE:-}" ]]; then
    bc_profile_components "${MANIFEST_PATH}" "${PROFILE}"
  else
    select_components_interactive
  fi
}

install_control_plane() {
  local component path
  mapfile -t SELECTED_COMPONENTS < <(selected_components)
  mapfile -t RESOLVED_COMPONENTS < <(bc_resolve_components "${MANIFEST_PATH}" "${SELECTED_COMPONENTS[@]}")

  printf "setup-project: installing components: %s\n" "${RESOLVED_COMPONENTS[*]}"

  for component in "${RESOLVED_COMPONENTS[@]}"; do
    while IFS= read -r path; do
      [[ -n "${path}" ]] && copy_path "${path}"
    done < <(bc_component_field "${MANIFEST_PATH}" "${component}" paths)

    while IFS= read -r path; do
      [[ -n "${path}" ]] && copy_path "${path}"
    done < <(bc_component_field "${MANIFEST_PATH}" "${component}" rootPaths)
  done

  ensure_gitignore_entry

  chmod +x "${TARGET_DIR}"/.beryl/scripts/*.sh 2>/dev/null || true
  chmod +x "${TARGET_DIR}"/.beryl/agent/scripts/*.sh 2>/dev/null || true
  chmod +x "${TARGET_DIR}"/.beryl/githooks/pre-commit 2>/dev/null || true
}

run_setup_checks() {
  local component hook
  local -A ran=()

  for component in "${RESOLVED_COMPONENTS[@]}"; do
    while IFS= read -r hook; do
      [[ -n "${hook}" ]] || continue
      [[ -z "${ran[${hook}]:-}" ]] || continue
      ran["${hook}"]=1

      case "${hook}" in
        sync-agent-env)
          run_with_optional_env "syncing generated agent shims" BERYL_SHIM_CONFLICT "${BERYL_SHIM_CONFLICT:-overwrite}" "${TARGET_DIR}/.beryl/agent/scripts/sync-agent-env.sh"
          ;;
        update-test-manifest)
          run_if_present "creating test manifest" "${TARGET_DIR}/.beryl/scripts/update-test-manifest.sh"
          ;;
        enable-githooks)
          enable_git_hook
          ;;
      esac
    done < <(bc_component_field "${MANIFEST_PATH}" "${component}" postInstall)
  done
}

enable_git_hook() {
  if [[ ! -d "${TARGET_DIR}/.git" ]]; then
    printf "setup-project: target is not a Git repository; skipped hook setup\n"
    return 0
  fi

  if confirm "Enable pre-commit hook with git config core.hooksPath .beryl/githooks?" "y"; then
    git -C "${TARGET_DIR}" config core.hooksPath .beryl/githooks
    printf "setup-project: enabled .beryl/githooks/pre-commit\n"
  fi
}

main() {
  local arg target_input stack runner

  PROFILE=""
  COMPONENTS_CSV=""
  TARGET_DIR=""

  while (($# > 0)); do
    arg="$1"
    case "${arg}" in
      -h|--help)
        usage
        exit 0
        ;;
      --profile)
        [[ $# -ge 2 ]] || fail "--profile requires a value"
        PROFILE="$2"
        shift 2
        ;;
      --profile=*)
        PROFILE="${arg#--profile=}"
        shift
        ;;
      --components)
        [[ $# -ge 2 ]] || fail "--components requires a value"
        COMPONENTS_CSV="$2"
        shift 2
        ;;
      --components=*)
        COMPONENTS_CSV="${arg#--components=}"
        shift
        ;;
      --*)
        fail "unknown argument: ${arg}"
        ;;
      *)
        [[ -z "${TARGET_DIR}" ]] || fail "only one TARGET_DIR is supported"
        TARGET_DIR="${arg}"
        shift
        ;;
    esac
  done

  [[ -z "${PROFILE}" || -z "${COMPONENTS_CSV}" ]] || fail "use --profile or --components, not both"

  if [[ -z "${TARGET_DIR}" ]]; then
    target_input="$(prompt "Target project directory")"
    TARGET_DIR="${target_input}"
  fi

  case "${TARGET_DIR}" in
    /*) ;;
    *) TARGET_DIR="${PWD}/${TARGET_DIR}" ;;
  esac
  TARGET_DIR="${TARGET_DIR%/}"
  ensure_target_dir "${TARGET_DIR}"

  printf "setup-project: target %s\n" "${TARGET_DIR}"
  install_control_plane
  ensure_git_repo

  stack="$(choose "Choose the closest project stack" \
    "JavaScript/TypeScript" \
    "Python" \
    "Go" \
    "Generic shell/custom" \
    "Use AI agent fallback")"

  if [[ "${stack}" == "Use AI agent fallback" ]]; then
    run_agent_fallback "stack options were insufficient"
  else
    case "${stack}" in
      "JavaScript/TypeScript")
        runner="$(choose "Choose the test runner" \
          "Jest" \
          "Vitest" \
          "Custom command" \
          "Use AI agent fallback")"
        ;;
      "Python")
        runner="$(choose "Choose the test runner" \
          "pytest + testmon" \
          "Custom command" \
          "Use AI agent fallback")"
        ;;
      "Go")
        runner="$(choose "Choose the test runner" \
          "go test" \
          "Custom command" \
          "Use AI agent fallback")"
        ;;
      *)
        runner="$(choose "Choose the test runner" \
          "Custom command" \
          "Use AI agent fallback")"
        ;;
    esac

    if [[ "${runner}" == "Use AI agent fallback" ]]; then
      run_agent_fallback "test runner options were insufficient"
    else
      configure_affected_tests "${stack}" "${runner}"
    fi
  fi

  run_setup_checks
  if confirm "Run ./.beryl/scripts/check.sh in the target now?" "y"; then
    run_if_present "running deterministic checks" "${TARGET_DIR}/.beryl/scripts/check.sh"
  fi

  if confirm "Use AI agent fallback for any remaining setup details?" "n"; then
    run_agent_fallback "user requested additional setup"
  fi

  printf "\nSetup complete for %s\n" "${TARGET_DIR}"
  printf "Next normal command: cd %q && ./.beryl/scripts/check.sh\n" "${TARGET_DIR}"
}

main "$@"
