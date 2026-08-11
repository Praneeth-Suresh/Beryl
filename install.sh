#!/bin/sh
set -eu

INSTALLER_VERSION="1"
# Canonical repository slug. Every default URL must be derived from this so a
# single owner rename cannot leave a stale (potentially claimable) slug behind.
REPO_SLUG="Praneeth-Suresh/Beryl"
DEFAULT_REF="main"
DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/$REPO_SLUG/$DEFAULT_REF"
DEFAULT_ARCHIVE_URL="https://codeload.github.com/$REPO_SLUG/tar.gz/$DEFAULT_REF"

fail() {
  if [ "${UPDATE_MODE:-0}" = "1" ]; then
    failed_phase="${UPDATE_PHASE:-validate}"
    failed_component="${UPDATE_COMPONENT:-unknown}"
    failed_path="${UPDATE_PATH:-.beryl/lock.json}"
    failed_reason="$*"
    failed_rollback="not-started"
    if [ "${ROLLBACK_READY:-0}" = "1" ]; then
      failed_rollback="$(rollback_update)"
    fi
    printf 'beryl: update failed phase=%s component=%s path=%s reason=%s rollback=%s\n' \
      "$failed_phase" "$failed_component" "$failed_path" "$failed_reason" "$failed_rollback" >&2
    exit 1
  fi
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  sh install.sh [--interactive] [--update] [--profile minimal|standard|full] [--components a,b] [--target DIR]

Options:
  --interactive              Prompt for component/profile and agent bootstrap choices.
  --update                   Safely update an existing Beryl installation. Requires
                             DIR/.beryl/lock.json and preserves target-owned files.
  --profile NAME              Install a named profile. Default: standard.
  --components a,b            Install explicit components plus dependencies.
  --target DIR                Install into DIR. Default: current directory.
  --source-dir DIR            Copy from a local Beryl checkout. Used by tests.
  --ref REF                   GitHub ref for remote install. Default: main.
  --raw-base-url URL          Raw GitHub base URL for install.sh and manifest.
  --archive-url URL           GitHub codeload tarball URL.
  --root-conflict POLICY      fail, overwrite, or skip root files. Default: fail.
  --enable-githooks           Set core.hooksPath=.beryl/githooks when installed.
  --expected-sha256 HEX       Fail unless the downloaded archive matches this
                              SHA-256 digest. Strongly recommended together
                              with --ref pinned to a tag or commit SHA.
  --dry-run                   Print resolved components and paths only.
  --bootstrap-agent           Enable optional post-install agent bootstrap after seed/sync.
  --agent-fallback [on|off]   Control fallback behavior when no agent runner is available. Default: on.
  --agent-runner [codex|claude|custom|off]
                             Choose agent runner override.
  --agent-command-template TPL Custom runner template for enterprise/private agents.
  --agent-policy [strict|interactive]
                             strict never edits outside the allowed scope; interactive prints manual next-step.
USAGE
}

split_csv() {
  printf "%s\n" "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d'
}

manifest_line() {
  kind="$1"
  name="$2"
  grep -F "\"kind\":\"${kind}\",\"name\":\"${name}\"" "$MANIFEST" || true
}

array_field_from_line() {
  line="$1"
  field="$2"
  printf "%s\n" "$line" | sed -n "s/^.*\"${field}\":\\[\\([^]]*\\)\\].*$/\\1/p" \
    | tr ',' '\n' \
    | sed 's/^"//; s/"$//; /^$/d'
}

profile_components() {
  line="$(manifest_line profile "$1")"
  [ -n "$line" ] || fail "unknown profile: $1"
  array_field_from_line "$line" components
}

component_field() {
  line="$(manifest_line component "$1")"
  [ -n "$line" ] || fail "unknown component: $1"
  array_field_from_line "$line" "$2"
}

component_names() {
  sed -n 's/^.*"kind":"component","name":"\([^"]*\)".*$/\1/p' "$MANIFEST"
}

init_interactive_io() {
  input_path="${BERYL_INSTALL_PROMPT_INPUT:-/dev/tty}"
  output_path="${BERYL_INSTALL_PROMPT_OUTPUT:-/dev/tty}"

  [ -r "$input_path" ] || fail "--interactive needs readable prompt input: $input_path"
  [ -w "$output_path" ] || fail "--interactive needs writable prompt output: $output_path"

  exec 3<"$input_path"
  exec 4>"$output_path"
}

prompt_interactive() {
  label="$1"
  default="${2:-}"
  value=""

  if [ -n "$default" ]; then
    printf "%s [%s]: " "$label" "$default" >&4
  else
    printf "%s: " "$label" >&4
  fi
  IFS= read -r value <&3 || fail "input ended while reading: $label"
  printf "%s" "${value:-$default}"
}

confirm_interactive() {
  label="$1"
  default="${2:-y}"
  value=""

  case "$default" in
    y|Y) suffix="Y/n" ;;
    n|N) suffix="y/N" ;;
    *) fail "confirm default must be y or n" ;;
  esac

  while true; do
    printf "%s [%s]: " "$label" "$suffix" >&4
    IFS= read -r value <&3 || fail "input ended while reading: $label"
    value="${value:-$default}"
    case "$value" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) printf "Please answer y or n.\n" >&4 ;;
    esac
  done
}

choose_install_components_interactive() {
  choice=""

  printf "\nChoose the Beryl component set\n" >&4
  printf "  1) Standard profile - agent instructions, shims, checks, and githooks\n" >&4
  printf "  2) Minimal profile - agent instructions and tool shims only\n" >&4
  printf "  3) Full profile - standard plus CI and driver workflows\n" >&4
  printf "  4) Custom components - comma-separated manifest components\n" >&4

  while true; do
    printf "Choose 1-4 [1]: " >&4
    IFS= read -r choice <&3 || fail "input ended while choosing Beryl component set"
    choice="${choice:-1}"
    case "$choice" in
      1) printf "profile:standard"; return 0 ;;
      2) printf "profile:minimal"; return 0 ;;
      3) printf "profile:full"; return 0 ;;
      4)
        printf "\nAvailable components:\n" >&4
        component_names | sed 's/^/  - /' >&4
        components_csv="$(prompt_interactive "Components to install" "agent-core,checks")"
        printf "components:%s" "$components_csv"
        return 0
        ;;
      *) printf "Please choose a listed option.\n" >&4 ;;
    esac
  done
}

existing_lock_components() {
  lockfile="$TARGET_DIR/.beryl/lock.json"
  [ -f "$lockfile" ] || return 0
  sed -n 's/^  "components": \[\(.*\)\].*$/\1/p' "$lockfile" \
    | tr ',' '\n' \
    | sed 's/^"//; s/"$//; /^$/d'
}

list_has() {
  printf "%s\n" "$1" | grep -qxF "$2"
}

json_array_from_lines() {
  first=1
  printf "["
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ","
    fi
    first=0
    printf "\"%s\"" "$item"
  done
  printf "]"
}

ensure_https() {
  case "$1" in
    https://*) ;;
    *) fail "remote downloads must use HTTPS: $1" ;;
  esac
}

# Root files a manifest may install outside .beryl/. The manifest is fetched
# from the network in remote installs, so its paths are untrusted input.
ROOT_PATH_ALLOWLIST="AGENTS.md
CLAUDE.md
.cursor/rules/agent-rules.md
.github/copilot-instructions.md
.codex/AGENTS.md
.github/workflows/deterministic-checks.yml
LICENSE
NOTICE"

validate_manifest_sanity() {
  set_update_context manifest manifest .beryl/beryl.components.json
  grep -q '"schemaVersion": 1' "$MANIFEST" || fail "manifest schemaVersion must be 1"
  grep -q '"installerVersion": "1"' "$MANIFEST" || fail "manifest installerVersion must be 1"
  UPDATE_PRESERVE_PATHS="$(manifest_top_array_field updatePreservePaths)"
  [ -n "$UPDATE_PRESERVE_PATHS" ] || fail "manifest updatePreservePaths must not be empty"
  for preserve_path in $UPDATE_PRESERVE_PATHS; do
    validate_update_preserve_path "$preserve_path"
  done
}

validate_install_path() {
  rel="$1"
  case "$rel" in
    ""|*[[:space:]]*) fail "manifest install path must not be empty or contain whitespace: $rel" ;;
    /*) fail "manifest install path must be repository-relative: $rel" ;;
    ..|../*|*/..|*/../*) fail "manifest install path must not contain ..: $rel" ;;
  esac
  case "$rel" in
    .beryl/*) return 0 ;;
  esac
  list_has "$ROOT_PATH_ALLOWLIST" "${rel%/}" \
    || fail "manifest install path outside .beryl/ is not in the root allowlist: $rel"
}

# updatePreservePaths is deliberately a top-level, one-line JSON array. The
# installer is intentionally dependency-free, so keep this format compatible
# with its constrained POSIX parser.
manifest_top_array_field() {
  top_field="$1"
  sed -n "s/^[[:space:]]*\"${top_field}\"[[:space:]]*:[[:space:]]*\[\([^]]*\)\][,[:space:]]*$/\1/p" "$MANIFEST" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^$/d'
}

validate_update_preserve_path() {
  preserve_rel="$1"
  validate_install_path "$preserve_rel"
  case "$preserve_rel" in
    .beryl/*) ;;
    *) fail "manifest update preserve path must stay under .beryl/: $preserve_rel" ;;
  esac
  case "$preserve_rel" in
    .beryl/|*\*|*\?*|*\[*|*]*)
      fail "manifest update preserve path must be an exact path or slash-suffixed subtree: $preserve_rel"
      ;;
  esac
}

set_update_context() {
  [ "${UPDATE_MODE:-0}" = "1" ] || return 0
  UPDATE_PHASE="$1"
  UPDATE_COMPONENT="$2"
  UPDATE_PATH="$3"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "need sha256sum or shasum for --expected-sha256"
  fi
}

verify_archive_digest() {
  archive_path="$1"
  [ -n "$EXPECTED_SHA256" ] || return 0
  actual_sha256="$(sha256_of "$archive_path")"
  if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
    fail "archive SHA-256 mismatch: expected $EXPECTED_SHA256 got $actual_sha256 (refusing to install)"
  fi
  printf "beryl: archive SHA-256 verified\n"
}

# fetch_https URL OUT
# --proto/--proto-redir keep every hop (including redirects) on HTTPS, so a
# redirect cannot downgrade the scheme after the initial ensure_https check.
fetch_https() {
  ensure_https "$1"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 3 \
    -fsSL "$1" -o "$2"
}

download_manifest() {
  set_update_context manifest manifest .beryl/beryl.components.json
  mkdir -p "$TMP_DIR"
  MANIFEST="$TMP_DIR/beryl.components.json"
  printf "beryl: fetching manifest from %s/.beryl/beryl.components.json\n" "$RAW_BASE_URL"
  fetch_https "$RAW_BASE_URL/.beryl/beryl.components.json" "$MANIFEST"
}

is_preserved_update_path() {
  preserved_rel="$1"
  for preserve_rule in $UPDATE_PRESERVE_PATHS; do
    case "$preserve_rule" in
      */)
        case "$preserved_rel" in "$preserve_rule"*) return 0 ;; esac
        ;;
      *) [ "$preserved_rel" = "$preserve_rule" ] && return 0 ;;
    esac
  done
  return 1
}

lock_array_field() {
  lock_path="$1"
  lock_field="$2"
  sed -n "s/^[[:space:]]*\"${lock_field}\"[[:space:]]*:[[:space:]]*\[\(.*\)\][,[:space:]]*$/\1/p" "$lock_path" \
    | tr ',' '\n' \
    | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//; /^$/d'
}

validate_existing_lock() {
  EXISTING_LOCK="$TARGET_DIR/.beryl/lock.json"
  [ -f "$EXISTING_LOCK" ] || fail "update requires an existing lockfile: .beryl/lock.json"
  grep -q '"installerVersion"[[:space:]]*:' "$EXISTING_LOCK" || fail "invalid existing lockfile: missing installerVersion"
  grep -q '"sourceRef"[[:space:]]*:' "$EXISTING_LOCK" || fail "invalid existing lockfile: missing sourceRef"
  grep -q '"requestedComponents"[[:space:]]*:' "$EXISTING_LOCK" || fail "invalid existing lockfile: missing requestedComponents"
  grep -q '"components"[[:space:]]*:' "$EXISTING_LOCK" || fail "invalid existing lockfile: missing components"
  LOCK_REQUESTED_COMPONENTS="$(lock_array_field "$EXISTING_LOCK" requestedComponents)"
  [ -n "$LOCK_REQUESTED_COMPONENTS" ] || fail "invalid existing lockfile: requestedComponents is empty"
  LOCK_COMPONENTS="$(lock_array_field "$EXISTING_LOCK" components)"
  [ -n "$LOCK_COMPONENTS" ] || fail "invalid existing lockfile: components is empty"
  OLD_MANAGED_PATHS="$(lock_array_field "$EXISTING_LOCK" managedPaths)"
  if grep -q '"managedPathsVersion"[[:space:]]*:[[:space:]]*1' "$EXISTING_LOCK" && [ -z "$OLD_MANAGED_PATHS" ]; then
    fail "invalid existing lockfile: managedPathsVersion requires managedPaths"
  fi
  if [ -z "$OLD_MANAGED_PATHS" ]; then
    LEGACY_LOCK="1"
    printf "beryl: update is migrating a legacy lockfile with conservative managed-path ownership\n"
  fi
}

validate_old_managed_paths() {
  [ "$UPDATE_MODE" = "1" ] || return 0
  [ "$LEGACY_LOCK" = "0" ] || return 0
  validated_old_paths=""
  for old_rel in $OLD_MANAGED_PATHS; do
    set_update_context validate lockfile "$old_rel"
    validate_install_path "$old_rel"
    list_has "$validated_old_paths" "$old_rel" && \
      update_fail validate lockfile "$old_rel" duplicate-managed-path
    is_preserved_update_path "$old_rel" && \
      update_fail validate lockfile "$old_rel" preserved-path-cannot-be-managed
    old_component="$(component_for_old_path "$old_rel")"
    [ "$old_component" != "unknown" ] || \
      update_fail validate lockfile "$old_rel" unowned-managed-path
    validated_old_paths="${validated_old_paths}
${old_rel}"
  done
}

component_for_old_path() {
  old_lookup_path="$1"
  for old_lookup_component in $(component_names); do
    for old_lookup_base in $(component_field "$old_lookup_component" paths) $(component_field "$old_lookup_component" rootPaths); do
      case "$old_lookup_base" in
        */)
          case "$old_lookup_path" in "$old_lookup_base"*) printf '%s' "$old_lookup_component"; return 0 ;; esac
          ;;
        *)
          [ "$old_lookup_path" = "$old_lookup_base" ] && { printf '%s' "$old_lookup_component"; return 0; }
          ;;
      esac
    done
  done
  printf 'unknown'
}

stage_local_paths() {
  STAGE_DIR="$TMP_DIR/stage"
  set_update_context stage source-tree "$SOURCE_DIR"
  mkdir -p "$STAGE_DIR" || fail "could not create staging directory"
  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    src="${SOURCE_DIR%/}/$rel"
    [ -e "$src" ] || [ -L "$src" ] || fail "source path missing: $rel"
    mkdir -p "$STAGE_DIR/$(dirname "$rel")" || fail "could not create staging parent: $rel"
    cp -pR "$src" "$STAGE_DIR/$rel" || fail "could not stage source path: $rel"
  done
}

stage_remote_paths() {
  archive="$TMP_DIR/beryl.tar.gz"
  STAGE_DIR="$TMP_DIR/stage"
  set_update_context stage archive "$ARCHIVE_URL"
  mkdir -p "$STAGE_DIR" || fail "could not create staging directory"

  printf "beryl: fetching archive %s\n" "$ARCHIVE_URL"
  fetch_https "$ARCHIVE_URL" "$archive" || fail "could not fetch archive"
  verify_archive_digest "$archive"
  tar -tzf "$archive" >"$TMP_DIR/archive-listing" || fail "could not inspect archive"
  prefix="$(sed -n '1s#/$##p; q' "$TMP_DIR/archive-listing")"
  [ -n "$prefix" ] || fail "could not detect archive prefix"

  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    tar -xzf "$archive" -C "$STAGE_DIR" --strip-components=1 "${prefix}/${rel%/}" 2>/dev/null || \
      tar -xzf "$archive" -C "$STAGE_DIR" --strip-components=1 "${prefix}/${rel}" 2>/dev/null || \
      fail "archive path missing: $rel"
  done
}

stage_managed_paths() {
  NEW_MANAGED_PATHS=""
  : >"$TMP_DIR/staged-paths" || fail "could not create staged path ledger"
  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    [ -e "$STAGE_DIR/$rel" ] || [ -L "$STAGE_DIR/$rel" ] || fail "staged path missing: $rel"
    find "$STAGE_DIR/$rel" \( -type f -o -type l \) -print >>"$TMP_DIR/staged-paths" || \
      fail "could not enumerate staged paths: $rel"
  done
  sed "s#^$STAGE_DIR/##" "$TMP_DIR/staged-paths" | awk '!seen[$0]++' >"$TMP_DIR/new-managed-paths" || \
    fail "could not write staged path ledger"
  while IFS= read -r staged_rel; do
    set_update_context stage "$(component_for_path "$staged_rel")" "$staged_rel"
    validate_install_path "$staged_rel"
  done <"$TMP_DIR/new-managed-paths"
  NEW_MANAGED_PATHS="$(cat "$TMP_DIR/new-managed-paths")"
  [ -n "$NEW_MANAGED_PATHS" ] || fail "staging produced no managed files"
}

component_for_path() {
  lookup_path="$1"
  for lookup_component in $RESOLVED_COMPONENTS; do
    for lookup_base in $(component_field "$lookup_component" paths) $(component_field "$lookup_component" rootPaths); do
      case "$lookup_base" in
        */)
          case "$lookup_path" in "$lookup_base"*) printf '%s' "$lookup_component"; return 0 ;; esac
          ;;
        *)
          [ "$lookup_path" = "$lookup_base" ] && { printf '%s' "$lookup_component"; return 0; }
          ;;
      esac
    done
  done
  printf 'unknown'
}

add_mutation_path() {
  mutation_path="$1"
  [ -n "$mutation_path" ] || return 0
  if ! list_has "$MUTATION_PATHS" "$mutation_path"; then
    MUTATION_PATHS="${MUTATION_PATHS}
${mutation_path}"
  fi
}

add_hook_mutation_paths() {
  # Hooks may create these files even when they did not exist before. Snapshot
  # explicit absence markers so a failed update removes only hook outputs.
  for hook_file in \
    .beryl/agent/project-brief.md \
    .beryl/agent/design-tree.md \
    .beryl/agent/architecture.md \
    .beryl/agent/ubiquitous-language.md \
    .beryl/agent/testing-policy.md \
    .beryl/agent/bootstrap-status.json \
    .beryl/agent/bootstrap-runner.log \
    tests/.manifest.sha256 \
    AGENTS.md CLAUDE.md .cursor/rules/agent-rules.md \
    .github/copilot-instructions.md .codex/AGENTS.md; do
    add_mutation_path "$hook_file"
  done
  add_seed_hook_mutation_paths
  add_configured_test_manifest_path
}

add_seed_hook_mutation_paths() {
  seed_template_root="$STAGE_DIR/.beryl/agent/templates/install"
  [ -d "$seed_template_root" ] || return 0
  find "$seed_template_root" -type f -print >"$TMP_DIR/seed-template-paths" || \
    update_fail snapshot agent-core .beryl/agent/templates/install enumerate-seed-templates
  while IFS= read -r seed_template; do
    seed_rel="${seed_template#${seed_template_root}/}"
    seed_output=".beryl/agent/$seed_rel"
    validate_install_path "$seed_output"
    add_mutation_path "$seed_output"
  done <"$TMP_DIR/seed-template-paths"
}

validate_target_relative_path() {
  target_rel="$1"
  case "$target_rel" in
    ""|/*|..|../*|*/..|*/../*|*[[:space:]]*)
      update_fail snapshot checks .beryl/agent/test-manifest.conf invalid-manifest-path
      ;;
  esac
}

add_configured_test_manifest_path() {
  manifest_config="$TARGET_DIR/.beryl/agent/test-manifest.conf"
  [ -f "$manifest_config" ] || return 0
  configured_manifest_path="$(sed -n 's/^[[:space:]]*MANIFEST_PATH="\([^"]*\)"[[:space:]]*$/\1/p' "$manifest_config")"
  [ -n "$configured_manifest_path" ] || \
    update_fail snapshot checks .beryl/agent/test-manifest.conf missing-manifest-path
  validate_target_relative_path "$configured_manifest_path"
  add_mutation_path "$configured_manifest_path"
}

validate_update_destination_path() {
  destination_rel="$1"
  destination_component="$2"
  destination_parent_rel="$(dirname "$destination_rel")"
  destination_parent="$TARGET_DIR"

  # All managed paths are relative and validated before staging. Walk their
  # existing parents one segment at a time: mkdir and cp would otherwise
  # follow a target-owned symlink out of the repository.
  if [ "$destination_parent_rel" != "." ]; then
    for destination_segment in $(printf '%s' "$destination_parent_rel" | tr '/' ' '); do
      destination_parent="$destination_parent/$destination_segment"
      if [ -L "$destination_parent" ]; then
        update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" parent-symlink
      fi
      if [ -e "$destination_parent" ] && [ ! -d "$destination_parent" ]; then
        update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" parent-not-directory
      fi
      if [ -d "$destination_parent" ]; then
        destination_physical="$(cd "$destination_parent" && pwd -P)" || \
          update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" parent-unreadable
        case "$destination_physical" in
          "$TARGET_DIR"|"$TARGET_DIR"/*) ;;
          *) update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" parent-outside-target ;;
        esac
      fi
    done
  fi

  destination_leaf="$TARGET_DIR/$destination_rel"
  if [ -d "$destination_leaf" ] && [ ! -L "$destination_leaf" ]; then
    update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" leaf-is-directory
  fi
}

snapshot_githooks_config() {
  [ "$UPDATE_MODE" = "1" ] || return 0
  [ "$ENABLE_GITHOOKS" = "1" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  set_update_context snapshot githooks .git/config
  git -C "$TARGET_DIR" config --local --list >/dev/null 2>&1 || \
    update_fail snapshot githooks .git/config read-config
  GIT_HOOKS_CONFIG_READY="1"
  if git -C "$TARGET_DIR" config --local --get core.hooksPath >"$ROLLBACK_DIR/git-hooks-path"; then
    GIT_HOOKS_CONFIG_PRESENT="1"
  else
    GIT_HOOKS_CONFIG_PRESENT="0"
  fi
}

snapshot_path() {
  snapshot_rel="$1"
  if list_has "$SNAPSHOT_PATHS" "$snapshot_rel"; then
    return 0
  fi
  SNAPSHOT_PATHS="${SNAPSHOT_PATHS}
${snapshot_rel}"
  snapshot_component="$(component_for_path "$snapshot_rel")"
  [ "$snapshot_component" = "unknown" ] && snapshot_component="hooks"
  set_update_context snapshot "$snapshot_component" "$snapshot_rel"
  validate_update_destination_path "$snapshot_rel" "$snapshot_component"
  snapshot_target="$TARGET_DIR/$snapshot_rel"
  if [ -e "$snapshot_target" ] || [ -L "$snapshot_target" ]; then
    mkdir -p "$ROLLBACK_DIR/files/$(dirname "$snapshot_rel")"
    cp -pR "$snapshot_target" "$ROLLBACK_DIR/files/$snapshot_rel" || fail "could not snapshot update path: $snapshot_rel"
  else
    mkdir -p "$ROLLBACK_DIR/missing/$(dirname "$snapshot_rel")"
    : >"$ROLLBACK_DIR/missing/$snapshot_rel"
  fi
}

snapshot_update_targets() {
  ROLLBACK_DIR="$TMP_DIR/rollback"
  mkdir -p "$ROLLBACK_DIR/files" "$ROLLBACK_DIR/missing"
  SNAPSHOT_PATHS=""
  MUTATION_PATHS=""
  for snapshot_rel in $NEW_MANAGED_PATHS $OLD_MANAGED_PATHS; do
    is_preserved_update_path "$snapshot_rel" || add_mutation_path "$snapshot_rel"
  done
  add_mutation_path .beryl/lock.json
  set_update_context snapshot hooks .beryl/agent
  add_hook_mutation_paths
  for snapshot_rel in $MUTATION_PATHS; do
    snapshot_path "$snapshot_rel"
  done
  snapshot_githooks_config
  ROLLBACK_READY="1"
}

rollback_update() {
  [ "${ROLLBACK_READY:-0}" = "1" ] || return 0
  rollback_result="ok"
  for snapshot_rel in $SNAPSHOT_PATHS; do
    rollback_target="$TARGET_DIR/$snapshot_rel"
    rollback_component="$(component_for_path "$snapshot_rel")"
    [ "$rollback_component" = "unknown" ] && rollback_component="hooks"
    validate_update_destination_path "$snapshot_rel" "$rollback_component" || rollback_result="failed"
    if [ -f "$ROLLBACK_DIR/missing/$snapshot_rel" ]; then
      rm -f "$rollback_target" 2>/dev/null || rollback_result="failed"
    else
      rm -f "$rollback_target" 2>/dev/null || rollback_result="failed"
      mkdir -p "$(dirname "$rollback_target")" || rollback_result="failed"
      cp -pR "$ROLLBACK_DIR/files/$snapshot_rel" "$rollback_target" 2>/dev/null || rollback_result="failed"
    fi
  done
  if [ "${GIT_HOOKS_CONFIG_READY:-0}" = "1" ]; then
    if [ "${GIT_HOOKS_CONFIG_PRESENT:-0}" = "1" ]; then
      git -C "$TARGET_DIR" config --local core.hooksPath "$(cat "$ROLLBACK_DIR/git-hooks-path")" \
        2>/dev/null || rollback_result="failed"
    else
      git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
    fi
  fi
  if [ "${BACKUP_CREATED:-0}" = "1" ]; then
    rm -rf "$BACKUP_DIR" 2>/dev/null || rollback_result="failed"
  fi
  printf '%s' "$rollback_result"
}

update_fail() {
  update_phase="$1"
  update_component="$2"
  update_path="$3"
  update_reason="$4"
  rollback_status="not-started"
  if [ "${ROLLBACK_READY:-0}" = "1" ]; then
    rollback_status="$(rollback_update)"
  fi
  printf 'beryl: update failed phase=%s component=%s path=%s reason=%s rollback=%s\n' \
    "$update_phase" "$update_component" "$update_path" "$update_reason" "$rollback_status" >&2
  exit 1
}

should_force_update_failure() {
  [ -n "${BERYL_UPDATE_FAIL_AT:-}" ] && [ "$BERYL_UPDATE_FAIL_AT" = "$1:$2" ]
}

apply_staged_file() {
  apply_rel="$1"
  apply_component="$(component_for_path "$apply_rel")"
  apply_src="$STAGE_DIR/$apply_rel"
  apply_dst="$TARGET_DIR/$apply_rel"

  if [ "$UPDATE_MODE" = "1" ] && is_preserved_update_path "$apply_rel"; then
    PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
    return 0
  fi
  if [ "$UPDATE_MODE" = "1" ] && [ "$LEGACY_LOCK" = "0" ] && \
     ! list_has "$OLD_MANAGED_PATHS" "$apply_rel" && { [ -e "$apply_dst" ] || [ -L "$apply_dst" ]; }; then
    printf 'beryl: update preserved unowned path %s\n' "$apply_rel"
    PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
    return 0
  fi
  if [ "$UPDATE_MODE" = "0" ]; then
    case "$apply_rel" in
      .beryl/*) ;;
      *)
        if { [ -e "$apply_dst" ] || [ -L "$apply_dst" ]; } && ! cmp -s "$apply_src" "$apply_dst" 2>/dev/null; then
          case "$ROOT_CONFLICT" in
            fail) fail "root file conflict: $apply_rel (use --root-conflict overwrite or skip)" ;;
            skip)
              printf 'beryl: skipped existing root file %s\n' "$apply_rel"
              PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
              return 0
              ;;
            overwrite) ;;
          esac
        fi
        ;;
    esac
  fi
  if [ "$UPDATE_MODE" = "1" ] && should_force_update_failure apply "$apply_rel"; then
    update_fail apply "$apply_component" "$apply_rel" forced
  fi
  if [ "$UPDATE_MODE" = "1" ]; then
    validate_update_destination_path "$apply_rel" "$apply_component"
  fi
  mkdir -p "$(dirname "$apply_dst")" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail apply "$apply_component" "$apply_rel" mkdir || fail "could not create destination: $apply_rel";
  }
  if [ "$UPDATE_MODE" = "1" ] && [ -L "$apply_dst" ]; then
    rm -f "$apply_dst" || update_fail apply "$apply_component" "$apply_rel" unlink-symlink
  fi
  cp -p "$apply_src" "$apply_dst" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail apply "$apply_component" "$apply_rel" copy || fail "could not install: $apply_rel";
  }
  APPLIED_MANAGED_PATHS="${APPLIED_MANAGED_PATHS}
${apply_rel}"
  UPDATED_COUNT=$((UPDATED_COUNT + 1))
  printf 'beryl: installed %s\n' "$apply_rel"
}

apply_removed_managed_paths() {
  [ "$UPDATE_MODE" = "1" ] || return 0
  [ "$LEGACY_LOCK" = "0" ] || return 0
  for removed_rel in $OLD_MANAGED_PATHS; do
    list_has "$NEW_MANAGED_PATHS" "$removed_rel" && continue
    is_preserved_update_path "$removed_rel" && continue
    removed_component="$(component_for_path "$removed_rel")"
    validate_update_destination_path "$removed_rel" "$removed_component"
    if should_force_update_failure apply "$removed_rel"; then
      update_fail apply "$removed_component" "$removed_rel" forced
    fi
    rm -f "$TARGET_DIR/$removed_rel" || update_fail apply "$removed_component" "$removed_rel" remove
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  done
}

run_post_install_hooks() {
  ran_hooks=""
  for component in $RESOLVED_COMPONENTS; do
    for hook in $(component_field "$component" postInstall); do
      if list_has "$ran_hooks" "$hook"; then
        continue
      fi
      ran_hooks="${ran_hooks}
${hook}"
      if [ "$UPDATE_MODE" = "1" ] && should_force_update_failure hook "$hook"; then
        update_fail hook "$component" "$hook" forced
      fi
      case "$hook" in
        seed-agent-context)
          if [ -x "$TARGET_DIR/.beryl/agent/scripts/seed-agent-context.sh" ]; then
            printf "beryl: running post-install hook: .beryl/agent/scripts/seed-agent-context.sh\n"
            if ! (cd "$TARGET_DIR" && BERYL_AGENT_TEMPLATE_CONFLICT="${BERYL_AGENT_TEMPLATE_CONFLICT:-skip}" ./.beryl/agent/scripts/seed-agent-context.sh); then
              [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" seed-agent-context failed
              fail "post-install hook failed: seed-agent-context"
            fi
          fi
          ;;
        sync-agent-env)
          if [ -x "$TARGET_DIR/.beryl/agent/scripts/sync-agent-env.sh" ]; then
            printf "beryl: running post-install hook: .beryl/agent/scripts/sync-agent-env.sh\n"
            if ! (cd "$TARGET_DIR" && BERYL_SHIM_CONFLICT="$ROOT_CONFLICT" ./.beryl/agent/scripts/sync-agent-env.sh); then
              [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" sync-agent-env failed
              fail "post-install hook failed: sync-agent-env"
            fi
          fi
          ;;
        bootstrap-agent-context)
          if [ "$UPDATE_MODE" = "1" ] && [ "$BOOTSTRAP_AGENT" != "1" ]; then
            printf "beryl: skipped agent bootstrap during update (pass --bootstrap-agent to rerun it)\n"
            continue
          fi
          if [ -x "$TARGET_DIR/.beryl/agent/scripts/bootstrap-agent-context.sh" ]; then
            printf "beryl: running post-install hook: .beryl/agent/scripts/bootstrap-agent-context.sh\n"
            if ! (cd "$TARGET_DIR" && \
              BERYL_AGENT_FALLBACK="$AGENT_FALLBACK" \
              BERYL_AGENT_RUNNER="${AGENT_RUNNER}" \
              BERYL_AGENT_COMMAND_TEMPLATE="${AGENT_COMMAND_TEMPLATE}" \
              BERYL_AGENT_POLICY="${AGENT_POLICY}" \
              BERYL_BOOTSTRAP_SOURCE_REF="$SOURCE_REF" \
              BERYL_BOOTSTRAP_INSTALLER_VERSION="$INSTALLER_VERSION" \
              BERYL_BOOTSTRAP_PROFILE="${PROFILE}" \
              BERYL_BOOTSTRAP_COMPONENTS="$RESOLVED_COMPONENTS" \
              ./.beryl/agent/scripts/bootstrap-agent-context.sh); then
              [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" bootstrap-agent-context failed
              fail "post-install hook failed: bootstrap-agent-context"
            fi
          fi
          ;;
        update-test-manifest)
          if [ -x "$TARGET_DIR/.beryl/scripts/update-test-manifest.sh" ]; then
            printf "beryl: running post-install hook: .beryl/scripts/update-test-manifest.sh\n"
            if ! (cd "$TARGET_DIR" && ./.beryl/scripts/update-test-manifest.sh); then
              [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" update-test-manifest failed
              fail "post-install hook failed: update-test-manifest"
            fi
          fi
          ;;
        enable-githooks)
          if [ "$ENABLE_GITHOOKS" = "1" ] && command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf "beryl: running post-install hook: git config core.hooksPath .beryl/githooks\n"
            if ! git -C "$TARGET_DIR" config core.hooksPath .beryl/githooks; then
              [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" enable-githooks failed
              fail "post-install hook failed: enable-githooks"
            fi
          else
            printf "beryl: skipped githook enablement (pass --enable-githooks inside a Git repo)\n"
          fi
          ;;
      esac
    done
  done
}

print_first_run_guide() {
  local target script_ref
  target="$(printf "%s" "$TARGET_DIR")"
  script_ref="$0"

  printf "beryl: first-run components selected:\n"
  printf "beryl: %s\n" "$RESOLVED_COMPONENTS" | sed 's/^/  - /'

  if [ ! -f "$TARGET_DIR/.beryl/driver/run.sh" ]; then
    printf "beryl: driver workflow files are not present yet (no .beryl/driver/run.sh).\n"
    printf "beryl: to enable driver usage, rerun with one of:\n"
    printf "beryl:   sh %s --profile full\n" "$script_ref"
    printf "beryl:   sh %s --components driver\n" "$script_ref"
  fi

  if printf "%s\n" "$RESOLVED_COMPONENTS" | grep -qx "githooks"; then
    printf "beryl: if you need the local pre-commit hook, run:\n"
    printf "beryl:   cd %s && git config core.hooksPath .beryl/githooks\n" "$target"
    printf "beryl: required before running this command:\n"
    printf "beryl:   - command must run inside a Git repo (or initialize one first)\n"
    printf "beryl:   - .git/config must be writable by this process\n"
    printf "beryl: common failure modes:\n"
    printf "beryl:   - fatal: not a git repository (run inside a repo)\n"
    printf "beryl:   - fatal: could not lock config file .git/config: Permission denied\n"
  fi
}

write_lockfile() {
  lock_tmp="$TMP_DIR/lock.json"
  mkdir -p "$TARGET_DIR/.beryl" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl mkdir
    fail "could not create .beryl for lockfile"
  }
  {
    printf "{\n"
    printf "  \"installerVersion\": \"%s\",\n" "$INSTALLER_VERSION"
    printf "  \"sourceRef\": \"%s\",\n" "$SOURCE_REF"
    printf "  \"source\": \"%s\",\n" "$SOURCE_LABEL"
    printf "  \"requestedComponents\": "
    printf "%s\n" "$REQUESTED_COMPONENTS" | json_array_from_lines
    printf ",\n"
    printf "  \"components\": "
    printf "%s\n" "$RESOLVED_COMPONENTS" | json_array_from_lines
    printf ",\n"
    printf "  \"managedPathsVersion\": 1,\n"
    printf "  \"managedPaths\": "
    printf "%s\n" "$FINAL_MANAGED_PATHS" | json_array_from_lines
    printf "\n}\n"
  } >"$lock_tmp" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl/lock.json write
    fail "could not write lockfile"
  }
  mv "$lock_tmp" "$TARGET_DIR/.beryl/lock.json" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl/lock.json replace
    fail "could not replace lockfile"
  }
  printf "beryl: wrote .beryl/lock.json\n"
}

verify_staged_update() {
  [ "$UPDATE_MODE" = "1" ] || return 0
  for verify_rel in $FINAL_MANAGED_PATHS; do
    verify_component="$(component_for_path "$verify_rel")"
    if should_force_update_failure verify "$verify_rel"; then
      update_fail verify "$verify_component" "$verify_rel" forced
    fi
    if ! cmp -s "$STAGE_DIR/$verify_rel" "$TARGET_DIR/$verify_rel"; then
      update_fail verify "$verify_component" "$verify_rel" content-mismatch
    fi
  done
}

create_update_backup() {
  [ "$UPDATE_MODE" = "1" ] || return 0
  backup_stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  backup_rel=".beryl/.updates/$backup_stamp"
  set_update_context backup backup "$backup_rel"
  validate_update_destination_path "$backup_rel" backup
  BACKUP_DIR="$TARGET_DIR/.beryl/.updates/$backup_stamp"
  mkdir -p "$BACKUP_DIR/files" || update_fail backup backup "$backup_rel" mkdir
  BACKUP_CREATED="1"
  for backup_rel in $SNAPSHOT_PATHS; do
    [ -e "$ROLLBACK_DIR/files/$backup_rel" ] || [ -L "$ROLLBACK_DIR/files/$backup_rel" ] || continue
    mkdir -p "$BACKUP_DIR/files/$(dirname "$backup_rel")" || update_fail backup backup "$backup_rel" mkdir
    cp -pR "$ROLLBACK_DIR/files/$backup_rel" "$BACKUP_DIR/files/$backup_rel" || \
      update_fail backup backup "$backup_rel" copy
  done
  printf 'beryl: update backup %s\n' "${BACKUP_DIR#${TARGET_DIR}/}"
}

PROFILE="standard"
COMPONENTS_CSV=""
INTERACTIVE="0"
EXPLICIT_COMPONENT_SELECTION="0"
UPDATE_MODE="0"
UPDATE_PHASE="validate"
UPDATE_COMPONENT="installer"
UPDATE_PATH="install.sh"
LEGACY_LOCK="0"
OLD_MANAGED_PATHS=""
LOCK_COMPONENTS=""
NEW_MANAGED_PATHS=""
APPLIED_MANAGED_PATHS=""
FINAL_MANAGED_PATHS=""
ROLLBACK_READY="0"
BACKUP_CREATED="0"
GIT_HOOKS_CONFIG_READY="0"
GIT_HOOKS_CONFIG_PRESENT="0"
UPDATED_COUNT="0"
PRESERVED_COUNT="0"
BOOTSTRAP_AGENT="0"
AGENT_FALLBACK="${BERYL_AGENT_FALLBACK:-on}"
AGENT_RUNNER="${BERYL_AGENT_RUNNER:-}"
AGENT_COMMAND_TEMPLATE="${BERYL_AGENT_COMMAND_TEMPLATE:-}"
AGENT_POLICY="${BERYL_AGENT_POLICY:-interactive}"
TARGET_DIR="$(pwd)"
SOURCE_DIR=""
SOURCE_REF="$DEFAULT_REF"
RAW_BASE_URL="$DEFAULT_RAW_BASE_URL"
ARCHIVE_URL="$DEFAULT_ARCHIVE_URL"
ROOT_CONFLICT="fail"
ENABLE_GITHOOKS="0"
EXPECTED_SHA256=""
DRY_RUN="0"
TMP_DIR="${TMPDIR:-/tmp}/beryl-install.$$"
MANIFEST=""
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --interactive)
      INTERACTIVE="1"
      shift
      ;;
    --update)
      UPDATE_MODE="1"
      shift
      ;;
    --profile)
      [ "$#" -ge 2 ] || fail "--profile requires a value"
      PROFILE="$2"
      EXPLICIT_COMPONENT_SELECTION="1"
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#--profile=}"
      EXPLICIT_COMPONENT_SELECTION="1"
      shift
      ;;
    --components)
      [ "$#" -ge 2 ] || fail "--components requires a value"
      COMPONENTS_CSV="$2"
      PROFILE=""
      EXPLICIT_COMPONENT_SELECTION="1"
      shift 2
      ;;
    --components=*)
      COMPONENTS_CSV="${1#--components=}"
      PROFILE=""
      EXPLICIT_COMPONENT_SELECTION="1"
      shift
      ;;
    --bootstrap-agent)
      BOOTSTRAP_AGENT="1"
      shift
      ;;
    --agent-fallback)
      [ "$#" -ge 2 ] || fail "--agent-fallback requires a value"
      AGENT_FALLBACK="$2"
      shift 2
      ;;
    --agent-fallback=*)
      AGENT_FALLBACK="${1#--agent-fallback=}"
      shift
      ;;
    --agent-runner)
      [ "$#" -ge 2 ] || fail "--agent-runner requires a value"
      AGENT_RUNNER="${2}"
      shift 2
      ;;
    --agent-runner=*)
      AGENT_RUNNER="${1#--agent-runner=}"
      shift
      ;;
    --agent-command-template)
      [ "$#" -ge 2 ] || fail "--agent-command-template requires a value"
      AGENT_COMMAND_TEMPLATE="${2}"
      shift 2
      ;;
    --agent-command-template=*)
      AGENT_COMMAND_TEMPLATE="${1#--agent-command-template=}"
      shift
      ;;
    --agent-policy)
      [ "$#" -ge 2 ] || fail "--agent-policy requires a value"
      AGENT_POLICY="${2}"
      shift 2
      ;;
    --agent-policy=*)
      AGENT_POLICY="${1#--agent-policy=}"
      shift
      ;;
    --target)
      [ "$#" -ge 2 ] || fail "--target requires a value"
      TARGET_DIR="$2"
      shift 2
      ;;
    --target=*)
      TARGET_DIR="${1#--target=}"
      shift
      ;;
    --source-dir)
      [ "$#" -ge 2 ] || fail "--source-dir requires a value"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --source-dir=*)
      SOURCE_DIR="${1#--source-dir=}"
      shift
      ;;
    --ref)
      [ "$#" -ge 2 ] || fail "--ref requires a value"
      SOURCE_REF="$2"
      RAW_BASE_URL="https://raw.githubusercontent.com/$REPO_SLUG/$SOURCE_REF"
      ARCHIVE_URL="https://codeload.github.com/$REPO_SLUG/tar.gz/$SOURCE_REF"
      shift 2
      ;;
    --ref=*)
      SOURCE_REF="${1#--ref=}"
      RAW_BASE_URL="https://raw.githubusercontent.com/$REPO_SLUG/$SOURCE_REF"
      ARCHIVE_URL="https://codeload.github.com/$REPO_SLUG/tar.gz/$SOURCE_REF"
      shift
      ;;
    --raw-base-url)
      [ "$#" -ge 2 ] || fail "--raw-base-url requires a value"
      RAW_BASE_URL="$2"
      shift 2
      ;;
    --raw-base-url=*)
      RAW_BASE_URL="${1#--raw-base-url=}"
      shift
      ;;
    --archive-url)
      [ "$#" -ge 2 ] || fail "--archive-url requires a value"
      ARCHIVE_URL="$2"
      shift 2
      ;;
    --archive-url=*)
      ARCHIVE_URL="${1#--archive-url=}"
      shift
      ;;
    --root-conflict)
      [ "$#" -ge 2 ] || fail "--root-conflict requires a value"
      ROOT_CONFLICT="$2"
      shift 2
      ;;
    --root-conflict=*)
      ROOT_CONFLICT="${1#--root-conflict=}"
      shift
      ;;
    --enable-githooks)
      ENABLE_GITHOOKS="1"
      shift
      ;;
    --expected-sha256)
      [ "$#" -ge 2 ] || fail "--expected-sha256 requires a value"
      EXPECTED_SHA256="$2"
      shift 2
      ;;
    --expected-sha256=*)
      EXPECTED_SHA256="${1#--expected-sha256=}"
      shift
      ;;
    --dry-run)
      DRY_RUN="1"
      shift
      ;;
    --*)
      fail "unknown argument: $1"
      ;;
    *)
      fail "unknown positional argument: $1"
      ;;
  esac
done

case "$ROOT_CONFLICT" in
  fail|overwrite|skip) ;;
  *) fail "--root-conflict must be fail, overwrite, or skip" ;;
esac
case "$AGENT_FALLBACK" in
  on|off) ;;
  *) fail "--agent-fallback must be on or off" ;;
esac
case "$AGENT_POLICY" in
  strict|interactive) ;;
  *) fail "--agent-policy must be strict or interactive" ;;
esac
case "$AGENT_RUNNER" in
  ""|codex|claude|custom|off) ;;
  *) fail "--agent-runner must be codex, claude, custom, or off" ;;
esac

if [ -n "$EXPECTED_SHA256" ]; then
  case "$EXPECTED_SHA256" in
    *[!0-9a-fA-F]*) fail "--expected-sha256 must be a 64-char hex digest" ;;
  esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || fail "--expected-sha256 must be a 64-char hex digest"
fi

mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ "$UPDATE_MODE" = "1" ]; then
  UPDATE_PHASE="validate"
  UPDATE_PATH=".beryl/lock.json"
  if [ "$BOOTSTRAP_AGENT" = "1" ]; then
    set_update_context validate agent-bootstrap --bootstrap-agent
    fail "--update cannot run agent bootstrap transactionally; run bootstrap separately after a successful update"
  fi
  validate_existing_lock
fi

if [ -n "$SOURCE_DIR" ]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
  MANIFEST="$SOURCE_DIR/.beryl/beryl.components.json"
  SOURCE_LABEL="$SOURCE_DIR"
  [ -f "$MANIFEST" ] || fail "missing local manifest: $MANIFEST"
else
  SOURCE_LABEL="$ARCHIVE_URL"
  download_manifest
fi
validate_manifest_sanity

if [ "$INTERACTIVE" = "1" ]; then
  init_interactive_io
  if [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ] && [ "$UPDATE_MODE" = "0" ]; then
    interactive_selection="$(choose_install_components_interactive)"
    case "$interactive_selection" in
      profile:*)
        PROFILE="${interactive_selection#profile:}"
        COMPONENTS_CSV=""
        ;;
      components:*)
        COMPONENTS_CSV="${interactive_selection#components:}"
        PROFILE=""
        ;;
      *) fail "unexpected interactive component selection: $interactive_selection" ;;
    esac
  fi

  if [ "$BOOTSTRAP_AGENT" != "1" ]; then
    if confirm_interactive "Have a coding agent help fill Beryl project context after install?" "n"; then
      BOOTSTRAP_AGENT="1"
    fi
  fi
fi

if [ "$UPDATE_MODE" = "1" ] && [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ]; then
  REQUESTED_COMPONENTS="$LOCK_REQUESTED_COMPONENTS"
  PROFILE=""
elif [ -n "$COMPONENTS_CSV" ]; then
  REQUESTED_COMPONENTS="$(split_csv "$COMPONENTS_CSV")"
else
  REQUESTED_COMPONENTS="$(profile_components "$PROFILE")"
fi
if [ "$BOOTSTRAP_AGENT" = "1" ]; then
  REQUESTED_COMPONENTS="${REQUESTED_COMPONENTS}
agent-bootstrap"
fi

if [ "$UPDATE_MODE" = "1" ]; then
  ALL_COMPONENTS="$(printf "%s\n" "$REQUESTED_COMPONENTS" | sed '/^$/d' | awk '!seen[$0]++')"
else
  EXISTING_COMPONENTS="$(existing_lock_components)"
  ALL_COMPONENTS="$(printf "%s\n%s\n" "$REQUESTED_COMPONENTS" "$EXISTING_COMPONENTS" | sed '/^$/d' | awk '!seen[$0]++')"
fi
changed=1
while [ "$changed" -eq 1 ]; do
  changed=0
  for component in $ALL_COMPONENTS; do
    [ -n "$(manifest_line component "$component")" ] || fail "unknown component: $component"
    for dep in $(component_field "$component" requires); do
      if ! list_has "$ALL_COMPONENTS" "$dep"; then
        ALL_COMPONENTS="${ALL_COMPONENTS}
${dep}"
        changed=1
      fi
    done
  done
done

RESOLVED_COMPONENTS=""
for component in $(component_names); do
  if list_has "$ALL_COMPONENTS" "$component"; then
    RESOLVED_COMPONENTS="${RESOLVED_COMPONENTS}
${component}"
  fi
done
RESOLVED_COMPONENTS="$(printf "%s\n" "$RESOLVED_COMPONENTS" | sed '/^$/d')"
REQUESTED_COMPONENTS="$(printf "%s\n" "$REQUESTED_COMPONENTS" | sed '/^$/d')"

INSTALL_PATHS=""
for component in $RESOLVED_COMPONENTS; do
  INSTALL_PATHS="${INSTALL_PATHS}
$(component_field "$component" paths)
$(component_field "$component" rootPaths)"
done
INSTALL_PATHS="$(printf "%s\n" "$INSTALL_PATHS" | sed '/^$/d' | awk '!seen[$0]++')"
for rel in $INSTALL_PATHS; do
  validate_install_path "$rel"
done
validate_old_managed_paths

printf "beryl: installer version %s\n" "$INSTALLER_VERSION"
printf "beryl: source ref %s\n" "$SOURCE_REF"
printf "beryl: resolved components: %s\n" "$(printf "%s" "$RESOLVED_COMPONENTS" | tr '\n' ' ')"

if [ "$DRY_RUN" = "1" ]; then
  printf "beryl: install paths:\n"
  printf "%s\n" "$INSTALL_PATHS" | sed 's/^/  /'
  exit 0
fi

UPDATE_PHASE="stage"
UPDATE_PATH="source"
if [ -n "$SOURCE_DIR" ]; then
  stage_local_paths
else
  stage_remote_paths
fi
stage_managed_paths

if [ "$UPDATE_MODE" = "1" ]; then
  if [ "$LEGACY_LOCK" = "1" ]; then
    # A legacy lock has no file ownership ledger. Do not delete anything from
    # it; only treat files present in the newly staged surface as managed.
    OLD_MANAGED_PATHS="$NEW_MANAGED_PATHS"
  fi
  snapshot_update_targets
fi

APPLIED_MANAGED_PATHS=""
UPDATE_PHASE="apply"
for rel in $NEW_MANAGED_PATHS; do
  apply_staged_file "$rel"
done
apply_removed_managed_paths
FINAL_MANAGED_PATHS=""
for final_rel in $APPLIED_MANAGED_PATHS; do
  is_preserved_update_path "$final_rel" && continue
  if ! list_has "$FINAL_MANAGED_PATHS" "$final_rel"; then
    FINAL_MANAGED_PATHS="${FINAL_MANAGED_PATHS}
${final_rel}"
  fi
done
FINAL_MANAGED_PATHS="$(printf '%s\n' "$FINAL_MANAGED_PATHS" | sed '/^$/d')"

if [ "$UPDATE_MODE" = "0" ]; then
  chmod +x "$TARGET_DIR"/.beryl/scripts/*.sh 2>/dev/null || true
  chmod +x "$TARGET_DIR"/.beryl/agent/scripts/*.sh 2>/dev/null || true
  chmod +x "$TARGET_DIR"/.beryl/githooks/pre-commit 2>/dev/null || true
else
  for chmod_rel in $APPLIED_MANAGED_PATHS; do
    case "$chmod_rel" in
      *.sh|.beryl/githooks/pre-commit)
        chmod +x "$TARGET_DIR/$chmod_rel" || \
          update_fail apply "$(component_for_path "$chmod_rel")" "$chmod_rel" chmod
        ;;
    esac
  done
fi

UPDATE_PHASE="hook"
run_post_install_hooks
UPDATE_PHASE="verify"
verify_staged_update
create_update_backup
UPDATE_PHASE="lock"
write_lockfile
print_first_run_guide
if [ "$UPDATE_MODE" = "1" ]; then
  printf 'beryl: update complete source-ref=%s components=%s updated=%s preserved=%s backup=%s\n' \
    "$SOURCE_REF" "$(printf '%s' "$RESOLVED_COMPONENTS" | tr '\n' ' ')" "$UPDATED_COUNT" "$PRESERVED_COUNT" \
    "${BACKUP_DIR#${TARGET_DIR}/}"
else
  printf "beryl: install complete in %s\n" "$TARGET_DIR"
fi
