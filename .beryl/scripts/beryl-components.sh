#!/usr/bin/env bash
set -euo pipefail

bc_fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

bc_manifest_line() {
  local manifest="$1"
  local kind="$2"
  local name="$3"

  grep -F "\"kind\":\"${kind}\",\"name\":\"${name}\"" "${manifest}" || true
}

bc_component_names() {
  local manifest="$1"
  sed -n 's/^.*"kind":"component","name":"\([^"]*\)".*$/\1/p' "${manifest}"
}

bc_profile_names() {
  local manifest="$1"
  sed -n 's/^.*"kind":"profile","name":"\([^"]*\)".*$/\1/p' "${manifest}"
}

bc_array_field_from_line() {
  local line="$1"
  local field="$2"
  local raw

  raw="$(printf "%s\n" "${line}" | sed -n "s/^.*\"${field}\":\\[\\([^]]*\\)\\].*$/\\1/p")"
  [[ -n "${raw}" ]] || return 0
  printf "%s\n" "${raw}" | tr ',' '\n' | sed 's/^"//; s/"$//; /^$/d'
}

bc_profile_components() {
  local manifest="$1"
  local profile="$2"
  local line

  line="$(bc_manifest_line "${manifest}" profile "${profile}")"
  [[ -n "${line}" ]] || bc_fail "unknown profile: ${profile}"
  bc_array_field_from_line "${line}" components
}

bc_component_field() {
  local manifest="$1"
  local component="$2"
  local field="$3"
  local line

  line="$(bc_manifest_line "${manifest}" component "${component}")"
  [[ -n "${line}" ]] || bc_fail "unknown component: ${component}"
  bc_array_field_from_line "${line}" "${field}"
}

bc_resolve_components() {
  local manifest="$1"
  shift
  local -a requested=("$@")
  local -A seen=()
  local -a ordered=()
  local component

  bc_resolve_visit() {
    local item="$1"
    local dep

    [[ -n "${item}" ]] || return 0
    [[ -z "${seen[${item}]:-}" ]] || return 0

    [[ -n "$(bc_manifest_line "${manifest}" component "${item}")" ]] || bc_fail "unknown component: ${item}"

    while IFS= read -r dep; do
      [[ -n "${dep}" ]] && bc_resolve_visit "${dep}"
    done < <(bc_component_field "${manifest}" "${item}" requires)

    seen["${item}"]=1
    ordered+=("${item}")
  }

  for component in "${requested[@]}"; do
    bc_resolve_visit "${component}"
  done

  printf "%s\n" "${ordered[@]}"
}

bc_validate_manifest() {
  local manifest="$1"
  local name component dep path hook profile selected

  [[ -f "${manifest}" ]] || bc_fail "missing manifest: ${manifest}"
  grep -q '"schemaVersion": 1' "${manifest}" || bc_fail "schemaVersion must be 1"
  grep -q '"installerVersion": "1"' "${manifest}" || bc_fail "installerVersion must be 1"

  while IFS= read -r component; do
    for name in requires paths rootPaths postInstall; do
      bc_component_field "${manifest}" "${component}" "${name}" >/dev/null || true
    done

    while IFS= read -r dep; do
      [[ -n "${dep}" ]] || continue
      [[ -n "$(bc_manifest_line "${manifest}" component "${dep}")" ]] || bc_fail "${component} requires unknown component ${dep}"
    done < <(bc_component_field "${manifest}" "${component}" requires)

    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      case "${path}" in
        .beryl/*) ;;
        *) bc_fail "${component} path must stay under .beryl/: ${path}" ;;
      esac
    done < <(bc_component_field "${manifest}" "${component}" paths)

    while IFS= read -r hook; do
      case "${hook}" in
        ""|sync-agent-env|update-test-manifest|enable-githooks) ;;
        *) bc_fail "${component} has unknown postInstall hook: ${hook}" ;;
      esac
    done < <(bc_component_field "${manifest}" "${component}" postInstall)
  done < <(bc_component_names "${manifest}")

  while IFS= read -r profile; do
    mapfile -t selected < <(bc_profile_components "${manifest}" "${profile}")
    ((${#selected[@]} > 0)) || bc_fail "profile has no components: ${profile}"
    for component in "${selected[@]}"; do
      [[ -n "$(bc_manifest_line "${manifest}" component "${component}")" ]] || bc_fail "profile ${profile} references unknown component ${component}"
    done
    bc_resolve_components "${manifest}" "${selected[@]}" >/dev/null
  done < <(bc_profile_names "${manifest}")
}
