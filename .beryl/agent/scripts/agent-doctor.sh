#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# Do not resolve directories or source paths.sh here. A doctor is itself the
# no-follow verifier for managed code and configuration, so it establishes its
# roots from the lexical invocation path only after every existing component is
# proven not to be a symlink.
validate_lexical_path() {
  local path="$1" current="" segment
  local -a segments=()

  [[ "${path}" == /* ]] || fail "invoked script path must be absolute after lexical expansion"
  IFS='/' read -r -a segments <<< "${path#/}"
  for segment in "${segments[@]}"; do
    [[ -n "${segment}" ]] || continue
    case "${segment}" in
      .|..) fail "invoked script path must not contain . or .. segments" ;;
    esac
    current="${current}/${segment}"
    [[ ! -L "${current}" ]] || fail "invoked script path has a symlink ancestor: ${current}"
  done
}

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ "${SCRIPT_PATH}" == ./* ]]; do
  SCRIPT_PATH="${SCRIPT_PATH#./}"
done
if [[ "${SCRIPT_PATH}" == /* ]]; then
  SCRIPT_ABS="${SCRIPT_PATH}"
else
  SCRIPT_ABS="${PWD%/}/${SCRIPT_PATH}"
fi
validate_lexical_path "${SCRIPT_ABS}"
SCRIPT_DIR="${SCRIPT_ABS%/*}"
case "${SCRIPT_DIR}" in
  */.beryl/agent/scripts) BERYL_ROOT="${SCRIPT_DIR%/agent/scripts}" ;;
  *) fail "agent-doctor.sh must be located at .beryl/agent/scripts/agent-doctor.sh" ;;
esac
REPO_ROOT="${BERYL_ROOT%/.beryl}"
[[ "${REPO_ROOT}" != "${BERYL_ROOT}" ]] || fail "agent-doctor.sh must have a .beryl parent"
validate_lexical_path "${BERYL_ROOT}"
validate_lexical_path "${REPO_ROOT}"

SOURCE="${BERYL_ROOT}/agent/tool-instruction-template.md"
LOCKFILE="${BERYL_ROOT}/lock.json"
MANIFEST="${BERYL_ROOT}/beryl.components.json"
INSTALL_MODE=""
INSTALLED_COMPONENTS=""
DEVELOPMENT_REQUESTED="0"
LOCKFILE_EXPLICIT="0"
ROOT_CONFLICT_POLICY=""
ROOT_CONFLICT_DECISIONS=""
PRESERVED_ROOT_DIGESTS=""
PRESERVED_ROOT_CONTRACTS=""

check_file() {
  local path="$1"
  [[ ! -L "${path}" ]] || fail "managed path must not be a symlink: ${path#${REPO_ROOT}/}"
  [[ -f "${path}" ]] || fail "missing file: ${path#${REPO_ROOT}/}"
}

check_exec() {
  local path="$1"
  check_file "${path}"
  [[ -x "${path}" ]] || fail "missing executable bit: ${path#${REPO_ROOT}/}"
}

usage() {
  cat <<'USAGE'
Usage: .beryl/agent/scripts/agent-doctor.sh [--development] [--lockfile PATH]

--development  Verify a Beryl source checkout. Requires the Beryl-owned
               .beryl/source-checkout.marker and is never inferred from host files.
--lockfile     Verify a regular candidate lock staged directly under .beryl/.
               Used by the lifecycle engine before its atomic lock commit.
USAGE
}

parse_args() {
  while (($#)); do
    case "$1" in
      --development) DEVELOPMENT_REQUESTED="1" ;;
      --lockfile)
        shift
        (($#)) || fail "--lockfile requires a value"
        LOCKFILE="$1"
        LOCKFILE_EXPLICIT="1"
        ;;
      --lockfile=*)
        LOCKFILE="${1#--lockfile=}"
        LOCKFILE_EXPLICIT="1"
        ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown argument: $1" ;;
    esac
    shift
  done
}

valid_sha256() {
  printf '%s\n' "$1" | grep -Eq '^[0-9a-fA-F]{64}$'
}

selected_root_component() {
  case "$1" in
    AGENTS.md|CLAUDE.md|.cursor/rules/agent-rules.md|.github/copilot-instructions.md|.codex/AGENTS.md)
      printf 'tool-shims' ;;
    LICENSE|NOTICE) printf 'agent-core' ;;
    .github/workflows/deterministic-checks.yml) printf 'ci' ;;
    *) return 1 ;;
  esac
}

preserved_digest_for_path() {
  local wanted="$1" entry path digest found=""
  for entry in ${PRESERVED_ROOT_DIGESTS}; do
    path="${entry%%:*}"
    digest="${entry#*:}"
    [[ "${path}" != "${entry}" && -n "${path}" && -n "${digest}" ]] || \
      fail "invalid lockfile: malformed preserved root contract digest"
    [[ "${path}" == "${wanted}" ]] || continue
    [[ -z "${found}" ]] || fail "invalid lockfile: duplicate preserved root contract digest: ${wanted}"
    found="${digest}"
  done
  printf '%s' "${found}"
}

validate_preserved_root_contracts() {
  local decision entry path component expected actual seen="" digest_seen=""

  [[ -n "${ROOT_CONFLICT_DECISIONS}" ]] || {
    [[ -z "${PRESERVED_ROOT_DIGESTS}" ]] || \
      fail "invalid lockfile: preserved root contract digests have no decisions"
    return 0
  }
  [[ "${ROOT_CONFLICT_POLICY}" == "skip" ]] || \
    fail "invalid lockfile: preserved root decisions require rootConflictPolicy skip"
  grep -q '"preservedRootContractDigestsVersion"[[:space:]]*:[[:space:]]*1' "${LOCKFILE}" || \
    fail "invalid lockfile: missing preservedRootContractDigestsVersion"
  [[ -n "${PRESERVED_ROOT_DIGESTS}" ]] || \
    fail "invalid lockfile: preserved root decisions require digests"

  for decision in ${ROOT_CONFLICT_DECISIONS}; do
    case "${decision}" in skip:*) path="${decision#skip:}" ;; *) fail "invalid lockfile: malformed root conflict decision: ${decision}" ;; esac
    component="$(selected_root_component "${path}" || true)"
    [[ -n "${component}" ]] || fail "invalid lockfile: unsupported preserved root contract: ${path}"
    has_component "${component}" || fail "invalid lockfile: preserved root contract not selected: ${path}"
    printf '%s\n' "${seen}" | grep -qxF "${path}" && \
      fail "invalid lockfile: duplicate root conflict decision: ${path}"
    seen="${seen}
${path}"
    expected="$(preserved_digest_for_path "${path}")"
    [[ -n "${expected}" ]] || fail "invalid lockfile: missing preserved root contract digest: ${path}"
    valid_sha256 "${expected}" || fail "invalid lockfile: invalid preserved root contract digest: ${path}"
    [[ -f "${REPO_ROOT}/${path}" && ! -L "${REPO_ROOT}/${path}" ]] || \
      fail "preserved external root contract must be a regular non-symlink file: ${path}"
    actual="$(sha256sum "${REPO_ROOT}/${path}" 2>/dev/null | awk '{print $1}' || true)"
    if [[ -z "${actual}" ]] && command -v shasum >/dev/null 2>&1; then
      actual="$(shasum -a 256 "${REPO_ROOT}/${path}" | awk '{print $1}')"
    fi
    [[ "${actual}" == "${expected}" ]] || \
      fail "preserved external root contract changed since install: ${path}"
    PRESERVED_ROOT_CONTRACTS="${PRESERVED_ROOT_CONTRACTS}
${path}"
  done

  for entry in ${PRESERVED_ROOT_DIGESTS}; do
    path="${entry%%:*}"
    expected="${entry#*:}"
    [[ "${path}" != "${entry}" ]] || fail "invalid lockfile: malformed preserved root contract digest"
    valid_sha256 "${expected}" || fail "invalid lockfile: invalid preserved root contract digest: ${path}"
    printf '%s\n' "${digest_seen}" | grep -qxF "${path}" && \
      fail "invalid lockfile: duplicate preserved root contract digest: ${path}"
    digest_seen="${digest_seen}
${path}"
    printf '%s\n' "${seen}" | grep -qxF "${path}" || \
      fail "invalid lockfile: preserved root contract digest has no decision: ${path}"
  done
}

development_marker_valid() {
  local marker="${BERYL_ROOT}/source-checkout.marker"
  [[ ! -L "${marker}" ]] || fail ".beryl/source-checkout.marker must not be a symlink"
  [[ -f "${marker}" ]] || fail "--development requires .beryl/source-checkout.marker"
  grep -qxF 'Beryl source checkout marker v1' "${marker}" || \
    fail "invalid .beryl/source-checkout.marker"
}

lock_array_field() {
  local field="$1"

  sed -n "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\[\(.*\)\][,[:space:]]*$/\1/p" "${LOCKFILE}" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^[[:space:]]*$/d'
}

lock_string_field() {
  local field="$1"
  sed -n "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*$/\1/p" "${LOCKFILE}" | head -n 1
}

component_declared() {
  local component="$1"
  grep -Fq "\"kind\":\"component\",\"name\":\"${component}\"" "${MANIFEST}"
}

has_component() {
  local component="$1"
  printf '%s\n' "${INSTALLED_COMPONENTS}" | grep -qxF "${component}"
}

line_list_has() {
  local list="$1" item="$2"
  # `grep -q` may close a pipeline before `printf` finishes writing a long
  # ownership ledger. With `pipefail` enabled that SIGPIPE becomes a false
  # negative membership result, so feed grep directly instead.
  grep -qxF -- "${item}" <<<"${list}"
}

normalize_component_set() {
  printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | sort -u
}

manifest_line() {
  local kind="$1" name="$2"
  grep -F "\"kind\":\"${kind}\",\"name\":\"${name}\"" "${MANIFEST}" || true
}

manifest_array_field() {
  local line="$1" field="$2"
  printf '%s\n' "${line}" | sed -n "s/^.*\"${field}\":\\[\\([^]]*\\)\\].*$/\\1/p" | tr ',' '\n' | sed 's/^"//; s/"$//; /^$/d'
}

manifest_component_field() {
  local component="$1" field="$2" line
  line="$(manifest_line component "${component}")"
  [[ -n "${line}" ]] || fail "invalid manifest: unknown component ${component}"
  manifest_array_field "${line}" "${field}"
}

resolve_requested_components() {
  local requested="$1" pending="${requested}" resolved="" component dependency changed
  changed=1
  while [[ "${changed}" == "1" ]]; do
    changed=0
    for component in ${pending}; do
      line_list_has "${resolved}" "${component}" && continue
      resolved="${resolved}
${component}"
      for dependency in $(manifest_component_field "${component}" requires); do
        if ! line_list_has "${pending}" "${dependency}"; then
          pending="${pending}
${dependency}"
          changed=1
        fi
      done
    done
  done
  printf '%s\n' "${resolved}" | sed '/^$/d'
}

component_path_is_selected() {
  local path="$1" component base bases
  while IFS= read -r component; do
    [[ -n "${component}" ]] || continue
    bases="$({ manifest_component_field "${component}" paths; manifest_component_field "${component}" rootPaths; })"
    while IFS= read -r base; do
      [[ -n "${base}" ]] || continue
      case "${base}" in
        */) [[ "${path}" == "${base}"* ]] && return 0 ;;
        *) [[ "${path}" == "${base}" ]] && return 0 ;;
      esac
    done <<<"${bases}"
  done <<<"${INSTALLED_COMPONENTS}"
  return 1
}

is_update_preserved_path() {
  local path="$1" rule
  while IFS= read -r rule; do
    [[ -n "${rule}" ]] || continue
    case "${rule}" in
      */) [[ "${path}" == "${rule}"* ]] && return 0 ;;
      *) [[ "${path}" == "${rule}" ]] && return 0 ;;
    esac
  done < <(sed -n 's/^[[:space:]]*"updatePreservePaths"[[:space:]]*:[[:space:]]*\[\([^]]*\)\][,[:space:]]*$/\1/p' "${MANIFEST}" | tr ',' '\n' | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^[[:space:]]*$/d')
  return 1
}

validate_lock_selection_and_surface() {
  local requested expected component seen="" normalized_expected normalized_resolved
  local managed digests path digest entry digest_path digest_value path_seen="" digest_seen="" matches

  grep -q '"requestedComponents"[[:space:]]*:' "${LOCKFILE}" || fail "invalid lockfile: missing requestedComponents"
  requested="$(lock_array_field requestedComponents)"
  [[ -n "${requested}" ]] || fail "invalid lockfile: requestedComponents is empty"
  for component in ${requested}; do
    component_declared "${component}" || fail "invalid lockfile: unknown requested component ${component}"
    line_list_has "${seen}" "${component}" && fail "invalid lockfile: duplicate requested component: ${component}"
    seen="${seen}
${component}"
  done
  seen=""
  for component in ${INSTALLED_COMPONENTS}; do
    component_declared "${component}" || fail "invalid lockfile: unknown component ${component}"
    line_list_has "${seen}" "${component}" && fail "invalid lockfile: duplicate component: ${component}"
    seen="${seen}
${component}"
  done
  expected="$(resolve_requested_components "${requested}")"
  normalized_expected="$(normalize_component_set "${expected}")"
  normalized_resolved="$(normalize_component_set "${INSTALLED_COMPONENTS}")"
  [[ "${normalized_expected}" == "${normalized_resolved}" ]] || \
    fail "invalid lockfile: components do not match requested dependency closure"

  grep -q '"managedPathsVersion"[[:space:]]*:[[:space:]]*1' "${LOCKFILE}" || fail "invalid lockfile: missing managedPathsVersion"
  grep -q '"managedPathDigestsVersion"[[:space:]]*:[[:space:]]*1' "${LOCKFILE}" || fail "invalid lockfile: missing managedPathDigestsVersion"
  managed="$(lock_array_field managedPaths)"
  digests="$(lock_array_field managedPathDigests)"
  [[ -n "${managed}" && -n "${digests}" ]] || fail "invalid lockfile: managed ownership ledger is empty"
  for path in ${managed}; do
    case "${path}" in ''|/*|..|../*|*/..|*/../*|*[[:space:]]*|*:*|*'"'*|*\\*) fail "invalid lockfile: malformed managed path: ${path}" ;; esac
    line_list_has "${path_seen}" "${path}" && fail "invalid lockfile: duplicate managed path: ${path}"
    path_seen="${path_seen}
${path}"
    is_update_preserved_path "${path}" && fail "invalid lockfile: target-owned preserved path is managed: ${path}"
    component_path_is_selected "${path}" || fail "invalid lockfile: managed path is outside selected surface: ${path}"
    matches="$(printf '%s\n' "${digests}" | sed -n "s#^${path}:##p" | wc -l | tr -d ' ')"
    [[ "${matches}" == "1" ]] || fail "invalid lockfile: missing or duplicate digest for ${path}"
    digest="$(printf '%s\n' "${digests}" | sed -n "s#^${path}:##p")"
    valid_sha256 "${digest}" || fail "invalid lockfile: invalid digest for ${path}"
  done
  for entry in ${digests}; do
    digest_path="${entry%%:*}"
    digest_value="${entry#*:}"
    [[ "${digest_path}" != "${entry}" ]] || fail "invalid lockfile: malformed managed digest"
    valid_sha256 "${digest_value}" || fail "invalid lockfile: invalid managed digest: ${digest_path}"
    line_list_has "${digest_seen}" "${digest_path}" && fail "invalid lockfile: duplicate managed digest: ${digest_path}"
    digest_seen="${digest_seen}
${digest_path}"
    line_list_has "${path_seen}" "${digest_path}" || fail "invalid lockfile: digest without managed path: ${digest_path}"
  done
}

load_install_context() {
  check_file "${MANIFEST}"

  if [[ "${LOCKFILE_EXPLICIT}" == "1" ]]; then
    case "${LOCKFILE}" in "${BERYL_ROOT}"/.lock.json.*) ;; *) fail "--lockfile must be a candidate directly under .beryl" ;; esac
  fi

  if [[ -e "${LOCKFILE}" || -L "${LOCKFILE}" ]]; then
    check_file "${LOCKFILE}"
    grep -q '"installerVersion"[[:space:]]*:' "${LOCKFILE}" || fail "invalid lockfile: missing installerVersion"
    grep -q '"components"[[:space:]]*:' "${LOCKFILE}" || fail "invalid lockfile: missing components"
    INSTALLED_COMPONENTS="$(lock_array_field components)"
    [[ -n "${INSTALLED_COMPONENTS}" ]] || fail "invalid lockfile: components is empty"

    local component
    while IFS= read -r component; do
      [[ -n "${component}" ]] || continue
      component_declared "${component}" || fail "invalid lockfile: unknown component ${component}"
    done <<<"${INSTALLED_COMPONENTS}"
    has_component agent-core || fail "invalid lockfile: agent-core is required"
    validate_lock_selection_and_surface
    ROOT_CONFLICT_POLICY="$(lock_string_field rootConflictPolicy)"
    [[ -n "${ROOT_CONFLICT_POLICY}" ]] || ROOT_CONFLICT_POLICY="fail"
    case "${ROOT_CONFLICT_POLICY}" in fail|overwrite|skip) ;; *) fail "invalid lockfile: rootConflictPolicy" ;; esac
    ROOT_CONFLICT_DECISIONS="$(lock_array_field rootConflictDecisions)"
    PRESERVED_ROOT_DIGESTS="$(lock_array_field preservedRootContractDigests)"
    validate_preserved_root_contracts
    INSTALL_MODE="locked"
    return 0
  fi

  if [[ "${DEVELOPMENT_REQUESTED}" == "1" ]]; then
    development_marker_valid
    INSTALLED_COMPONENTS="$(sed -n 's/^.*"kind":"component","name":"\([^"]*\)".*$/\1/p' "${MANIFEST}")"
    INSTALL_MODE="development"
    return 0
  fi

  fail "missing lockfile: .beryl/lock.json"
}

check_agent_core() {
  local required_canonical=(
    "${BERYL_ROOT}/agent/README.md"
    "${BERYL_ROOT}/agent/project-brief.md"
    "${BERYL_ROOT}/agent/design-tree.md"
    "${BERYL_ROOT}/agent/ubiquitous-language.md"
    "${BERYL_ROOT}/agent/architecture.md"
    "${BERYL_ROOT}/agent/testing-policy.md"
    "${BERYL_ROOT}/agent/security-policy.md"
    "${BERYL_ROOT}/agent/agent-rules.md"
    "${BERYL_ROOT}/agent/task-routing.md"
    "${BERYL_ROOT}/agent/tool-instruction-template.md"
    "${BERYL_ROOT}/agent/mcp.json"
    "${BERYL_ROOT}/agent/module-routing.md"
    "${BERYL_ROOT}/agent/templates/install/project-brief.md"
    "${BERYL_ROOT}/agent/templates/install/design-tree.md"
    "${BERYL_ROOT}/agent/templates/install/architecture.md"
    "${BERYL_ROOT}/agent/templates/install/ubiquitous-language.md"
    "${BERYL_ROOT}/agent/templates/install/testing-policy.md"
    "${BERYL_ROOT}/agent/templates/install/adr/0001-record-architecture-decisions.md"
    "${BERYL_ROOT}/agent/adr/0001-record-architecture-decisions.md"
    "${BERYL_ROOT}/agent/skills/planning/SKILL.md"
    "${BERYL_ROOT}/agent/skills/adding-features/SKILL.md"
    "${BERYL_ROOT}/agent/skills/initial-build/SKILL.md"
    "${BERYL_ROOT}/agent/skills/debugging/SKILL.md"
    "${BERYL_ROOT}/agent/skills/explaining-codebase/SKILL.md"
    "${BERYL_ROOT}/agent/skills/grill-me/SKILL.md"
    "${BERYL_ROOT}/agent/skills/interview-me/SKILL.md"
    "${BERYL_ROOT}/agent/skills/testing-vertical-slices/SKILL.md"
    "${BERYL_ROOT}/agent/skills/improving-architecture/SKILL.md"
    "${BERYL_ROOT}/agent/skills/tracking-entropy/SKILL.md"
  )
  local file
  for file in "${required_canonical[@]}"; do
    check_file "${file}"
  done

  local required_exec=(
    "${BERYL_ROOT}/agent/scripts/agent-doctor.sh"
    "${BERYL_ROOT}/agent/scripts/seed-agent-context.sh"
    "${BERYL_ROOT}/agent/scripts/sync-agent-env.sh"
  )
  for file in "${required_exec[@]}"; do
    check_exec "${file}"
  done

  check_file "${REPO_ROOT}/LICENSE"
  check_file "${REPO_ROOT}/NOTICE"

  if [[ -L "${REPO_ROOT}/.gitignore" ]]; then
    fail ".gitignore must not be a symlink"
  fi
  if [[ -f "${REPO_ROOT}/.gitignore" ]]; then
    grep -qxF ".beryl/agent/session-state.md" "${REPO_ROOT}/.gitignore" || \
      fail ".gitignore must ignore .beryl/agent/session-state.md"
  else
    fail "missing file: .gitignore"
  fi
}

check_tool_shims() {
  [[ -e "${REPO_ROOT}/.codex" && ! -d "${REPO_ROOT}/.codex" ]] && \
    fail ".codex must be a directory for generated shim output"

  local shim_targets=(
    "${REPO_ROOT}/AGENTS.md"
    "${REPO_ROOT}/CLAUDE.md"
    "${REPO_ROOT}/.cursor/rules/agent-rules.md"
    "${REPO_ROOT}/.github/copilot-instructions.md"
    "${REPO_ROOT}/.codex/AGENTS.md"
  )
  local target
  for target in "${shim_targets[@]}"; do
    local rel="${target#${REPO_ROOT}/}"
    if printf '%s\n' "${PRESERVED_ROOT_CONTRACTS}" | grep -qxF "${rel}"; then
      continue
    fi
    check_file "${target}"
    cmp -s "${SOURCE}" "${target}" || \
      fail "stale shim: ${target#${REPO_ROOT}/}. Run .beryl/agent/scripts/sync-agent-env.sh"
  done
}

check_checks_component() {
  local required_exec=(
    "${BERYL_ROOT}/scripts/check.sh"
    "${BERYL_ROOT}/scripts/check-md.sh"
    "${BERYL_ROOT}/scripts/check-affected.sh"
    "${BERYL_ROOT}/scripts/check-tests-unchanged.sh"
    "${BERYL_ROOT}/scripts/check-project.sh"
    "${BERYL_ROOT}/scripts/validate-components.sh"
    "${BERYL_ROOT}/scripts/check-install-surface.sh"
    "${BERYL_ROOT}/scripts/check-initial-build-workflow.sh"
    "${BERYL_ROOT}/scripts/check-secrets.sh"
    "${BERYL_ROOT}/scripts/update-test-manifest.sh"
    "${BERYL_ROOT}/scripts/paths.sh"
  )
  local file
  for file in "${required_exec[@]}"; do
    check_exec "${file}"
  done
  check_file "${BERYL_ROOT}/agent/test-manifest.conf"
  check_file "${BERYL_ROOT}/agent/affected-tests.conf"
  check_file "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
  # test-manifest-lib.sh sources safe-conf.sh when tm_load_manifest_config
  # runs. Validate both the code and the two loaded configurations before
  # sourcing any managed file.
  check_file "${BERYL_ROOT}/scripts/safe-conf.sh"

  # shellcheck source=../../scripts/test-manifest-lib.sh
  source "${BERYL_ROOT}/scripts/test-manifest-lib.sh"
  tm_load_manifest_config "${REPO_ROOT}" "${BERYL_ROOT}"
  check_file "${TM_MANIFEST_ABS}"
}

check_githooks_component() {
  check_exec "${BERYL_ROOT}/githooks/pre-commit"
}

check_ci_component() {
  check_file "${REPO_ROOT}/.github/workflows/deterministic-checks.yml"
}

check_driver_component() {
  check_exec "${BERYL_ROOT}/driver/run.sh"
}

parse_args "$@"
printf "Checking agent workspace (%s installation)...\n" "${INSTALL_MODE:-resolving}"
load_install_context
check_agent_core
has_component tool-shims && check_tool_shims
has_component checks && check_checks_component
has_component githooks && check_githooks_component
has_component ci && check_ci_component
has_component driver && check_driver_component

if [[ -n "${PRESERVED_ROOT_CONTRACTS}" ]]; then
  printf "Agent workspace ready (ready-with-preserved-external-contracts; %s; components: %s).\n" \
    "${INSTALL_MODE}" "$(printf '%s' "${INSTALLED_COMPONENTS}" | tr '\n' ' ')"
  printf 'WARNING: ready-with-preserved-external-contracts; Beryl does not enforce: %s\n' \
    "$(printf '%s\n' "${PRESERVED_ROOT_CONTRACTS}" | sed '/^$/d' | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
else
  printf "Agent workspace ready (ready; %s; components: %s).\n" \
    "${INSTALL_MODE}" "$(printf '%s' "${INSTALLED_COMPONENTS}" | tr '\n' ' ')"
fi
