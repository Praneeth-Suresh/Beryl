#!/bin/sh
set -eu

INSTALLER_VERSION="1"
# Canonical repository slug. Every default URL must be derived from this so a
# single owner rename cannot leave a stale (potentially claimable) slug behind.
REPO_SLUG="Praneeth-Suresh/Beryl"
DEFAULT_REF="main"
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
  if [ "${INITIAL_TRANSACTION_READY:-0}" = "1" ]; then
    failed_phase="${INSTALL_PHASE:-apply}"
    failed_path="${INSTALL_PATH:-.beryl}"
    failed_rollback="$(rollback_initial_install)"
    printf 'beryl: install failed phase=%s path=%s reason=%s rollback=%s\n' \
      "$failed_phase" "$failed_path" "$*" "$failed_rollback" >&2
    exit 1
  fi
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  sh install.sh [--interactive] [--update] [--restore BACKUP_ID|--uninstall|--adopt-existing] [--profile minimal|standard|full] [--components a,b] [--target DIR]

Options:
  --interactive              Prompt for component/profile choices. Agent bootstrap
                             is always a separate post-transaction action.
  --update                   Safely update an existing Beryl installation. Requires
                             DIR/.beryl/lock.json and preserves target-owned files.
  --restore BACKUP_ID         Restore one retained update backup; requires explicit
                             historical profile/components authorization.
  --current-source-dir DIR    For restore, Git checkout proving files from the
                             currently installed (newer) release before removal.
  --current-profile NAME      For restore, explicitly authorize the current
                             component surface before removing newer files.
  --current-components a,b    Explicit current restore component authorization.
  --uninstall                Remove only explicitly selected, unchanged,
                             digest-proven Beryl-managed files.
  --adopt-existing           Record ownership of an identical, unlocked Beryl surface
                             without replacing target content.
  --profile NAME              Install a named profile. Default: standard.
  --components a,b            Install explicit components plus dependencies.
  --target DIR                Install into DIR. Default: current directory.
  --source-dir DIR            Copy from a local Beryl Git checkout. Used by tests.
  --ref REF                   Remote lifecycle requires a full 40-character commit
                              SHA. Locked updates reuse the recorded source ref
                              unless an explicit replacement is supplied.
  --archive-url URL           GitHub codeload tarball URL.
  --root-conflict POLICY      fail, overwrite, or skip root files. Default: fail.
  --enable-githooks           Set core.hooksPath=.beryl/githooks when installed.
  --hook-conflict POLICY      fail, preserve, or replace an existing hooks path.
                              Default: fail when --enable-githooks is supplied.
  --expected-sha256 HEX       Required for every remote lifecycle archive. Locked
                              remote updates reuse the recorded digest unless an
                              explicit replacement source/digest is supplied.
  --dry-run                   Print resolved components and paths only.
  --bootstrap-agent           Run agent bootstrap against an existing locked Beryl
                             install. This is a separate post-install action.
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

json_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

ensure_https() {
  case "$1" in
    https://*) ;;
    *) fail "remote downloads must use HTTPS: $1" ;;
  esac
}

set_default_remote_urls_for_ref() {
  ARCHIVE_URL="https://codeload.github.com/$REPO_SLUG/tar.gz/$SOURCE_REF"
}

validate_source_ref() {
  source_ref_to_validate="${1:-$SOURCE_REF}"
  case "$source_ref_to_validate" in
    ""|*[[:space:]]*|/*|*'..'*|*'?'*|*'#'*)
      fail "--ref must be a non-empty Git ref without traversal or URL delimiters"
      ;;
  esac
}

is_full_commit_sha() {
  printf '%s\n' "$1" | grep -Eq '^[0-9a-fA-F]{40}$'
}

enforce_remote_archive_trust() {
  [ -z "$SOURCE_DIR" ] || return 0
  is_full_commit_sha "$SOURCE_REF" || \
    fail "remote lifecycle requires --ref to be a full 40-character commit SHA"
  [ -n "$EXPECTED_SHA256" ] || \
    fail "remote lifecycle requires --expected-sha256 for the selected archive"
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

# Lifecycle ownership is content-addressed.  A digest is recorded only for a
# regular file that the transaction actually left in the target; recovery never
# treats an absent digest (including a legacy lock) as permission to delete.
managed_digest_entries() {
  for digest_rel in $FINAL_MANAGED_PATHS; do
    digest_file="$TARGET_DIR/$digest_rel"
    [ -f "$digest_file" ] && [ ! -L "$digest_file" ] || \
      fail "cannot record digest for non-regular managed file: $digest_rel"
    printf '%s:%s\n' "$digest_rel" "$(sha256_of "$digest_file")"
  done
}

# A skipped root contract stays target-owned. Its digest is an integrity
# boundary: readiness may report external ownership only while the exact file
# that the installer observed remains in place.
preserved_root_contract_digest_entries() {
  for preserved_decision in $ROOT_CONFLICT_DECISIONS; do
    case "$preserved_decision" in
      skip:*) preserved_rel="${preserved_decision#skip:}" ;;
      *) fail "cannot record malformed root conflict decision: $preserved_decision" ;;
    esac
    list_has "$INSTALL_PATHS" "$preserved_rel" || \
      fail "cannot record unselected preserved root contract: $preserved_rel"
    case "$preserved_rel" in .beryl/*) fail "cannot record non-root preserved contract: $preserved_rel" ;; esac
    preserved_file="$TARGET_DIR/$preserved_rel"
    [ -f "$preserved_file" ] && [ ! -L "$preserved_file" ] || \
      fail "cannot record digest for non-regular preserved root contract: $preserved_rel"
    printf '%s:%s\n' "$preserved_rel" "$(sha256_of "$preserved_file")"
  done
}

valid_sha256() {
  printf '%s\n' "$1" | grep -Eq '^[0-9a-fA-F]{64}$'
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

# Remote planning is driven only by the digest-verified archive.  In
# particular, never let a separately fetched raw manifest select paths that a
# different archive later supplies.
prepare_remote_release() {
  REMOTE_ARCHIVE="$TMP_DIR/beryl.tar.gz"
  set_update_context manifest archive "$ARCHIVE_URL"
  printf "beryl: fetching archive %s\n" "$ARCHIVE_URL"
  fetch_https "$ARCHIVE_URL" "$REMOTE_ARCHIVE" || fail "could not fetch archive"
  verify_archive_digest "$REMOTE_ARCHIVE"
  tar -tzf "$REMOTE_ARCHIVE" >"$TMP_DIR/archive-listing" || fail "could not inspect archive"
  REMOTE_ARCHIVE_PREFIX="$(sed -n '1s#/$##p; q' "$TMP_DIR/archive-listing")"
  [ -n "$REMOTE_ARCHIVE_PREFIX" ] || fail "could not detect archive prefix"
  MANIFEST="$TMP_DIR/beryl.components.json"
  tar -xOzf "$REMOTE_ARCHIVE" "$REMOTE_ARCHIVE_PREFIX/.beryl/beryl.components.json" >"$MANIFEST" 2>/dev/null || \
    fail "verified archive lacks manifest"
  [ -s "$MANIFEST" ] || fail "verified archive manifest is empty"
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

lock_string_field() {
  lock_path="$1"
  lock_field="$2"
  sed -n "s/^[[:space:]]*\"${lock_field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*$/\1/p" "$lock_path" | head -n 1
}

lock_boolean_field() {
  lock_path="$1"
  lock_field="$2"
  sed -n "s/^[[:space:]]*\"${lock_field}\"[[:space:]]*:[[:space:]]*\(true\|false\).*$/\1/p" "$lock_path" | head -n 1
}

root_contract_component() {
  case "$1" in
    AGENTS.md|CLAUDE.md|.cursor/rules/agent-rules.md|.github/copilot-instructions.md|.codex/AGENTS.md)
      printf '%s\n' tool-shims
      ;;
    LICENSE|NOTICE)
      printf '%s\n' agent-core
      ;;
    .github/workflows/deterministic-checks.yml)
      printf '%s\n' ci
      ;;
    *) return 1 ;;
  esac
}

lock_preserved_digest_for_path() {
  wanted_path="$1"
  found_digest=""
  for digest_entry in $LOCK_PRESERVED_ROOT_DIGESTS; do
    digest_path="${digest_entry%%:*}"
    digest_value="${digest_entry#*:}"
    [ "$digest_path" != "$digest_entry" ] && [ -n "$digest_path" ] && [ -n "$digest_value" ] || \
      fail "invalid existing lockfile: malformed preserved root contract digest"
    [ "$digest_path" = "$wanted_path" ] || continue
    [ -z "$found_digest" ] || \
      fail "invalid existing lockfile: duplicate preserved root contract digest: $wanted_path"
    found_digest="$digest_value"
  done
  printf '%s' "$found_digest"
}

# Do not let an update silently bless a root contract that changed after the
# lock was written. A new digest is valid only after the old lock proves that
# the target-owned file is the same one the prior lifecycle observed.
validate_existing_preserved_root_contracts() {
  [ -n "$LOCK_ROOT_CONFLICT_DECISIONS" ] || {
    [ -z "$LOCK_PRESERVED_ROOT_DIGESTS" ] || \
      fail "invalid existing lockfile: preserved root contract digests have no decisions"
    return 0
  }
  [ "$LOCK_ROOT_CONFLICT" = "skip" ] || \
    fail "invalid existing lockfile: preserved root decisions require rootConflictPolicy skip"
  grep -q '"preservedRootContractDigestsVersion"[[:space:]]*:[[:space:]]*1' "$EXISTING_LOCK" || \
    fail "invalid existing lockfile: missing preservedRootContractDigestsVersion"
  [ -n "$LOCK_PRESERVED_ROOT_DIGESTS" ] || \
    fail "invalid existing lockfile: preserved root decisions require digests"

  validated_decisions=""
  validated_digests=""
  for locked_decision in $LOCK_ROOT_CONFLICT_DECISIONS; do
    case "$locked_decision" in
      skip:*) locked_path="${locked_decision#skip:}" ;;
      *) fail "invalid existing lockfile: malformed root conflict decision: $locked_decision" ;;
    esac
    locked_component="$(root_contract_component "$locked_path" || true)"
    [ -n "$locked_component" ] || \
      fail "invalid existing lockfile: unsupported preserved root contract: $locked_path"
    list_has "$LOCK_COMPONENTS" "$locked_component" || \
      fail "invalid existing lockfile: preserved root contract not selected: $locked_path"
    list_has "$validated_decisions" "$locked_path" && \
      fail "invalid existing lockfile: duplicate root conflict decision: $locked_path"
    validated_decisions="${validated_decisions}
$locked_path"
    locked_digest="$(lock_preserved_digest_for_path "$locked_path")"
    [ -n "$locked_digest" ] || \
      fail "invalid existing lockfile: missing preserved root contract digest: $locked_path"
    valid_sha256 "$locked_digest" || \
      fail "invalid existing lockfile: invalid preserved root contract digest: $locked_path"
    [ -f "$TARGET_DIR/$locked_path" ] && [ ! -L "$TARGET_DIR/$locked_path" ] || \
      fail "preserved external root contract must be a regular non-symlink file: $locked_path"
    [ "$(sha256_of "$TARGET_DIR/$locked_path")" = "$locked_digest" ] || \
      fail "preserved external root contract changed since install: $locked_path"
  done

  for digest_entry in $LOCK_PRESERVED_ROOT_DIGESTS; do
    digest_path="${digest_entry%%:*}"
    digest_value="${digest_entry#*:}"
    [ "$digest_path" != "$digest_entry" ] && valid_sha256 "$digest_value" || \
      fail "invalid existing lockfile: malformed preserved root contract digest"
    list_has "$validated_digests" "$digest_path" && \
      fail "invalid existing lockfile: duplicate preserved root contract digest: $digest_path"
    validated_digests="${validated_digests}
$digest_path"
    list_has "$validated_decisions" "$digest_path" || \
      fail "invalid existing lockfile: preserved root contract digest has no decision: $digest_path"
  done
}

validate_existing_lock() {
  EXISTING_LOCK="$TARGET_DIR/.beryl/lock.json"
  [ ! -L "$TARGET_DIR/.beryl" ] || update_fail validate lockfile .beryl parent-symlink
  [ -d "$TARGET_DIR/.beryl" ] || update_fail validate lockfile .beryl parent-not-directory
  [ ! -L "$EXISTING_LOCK" ] || update_fail validate lockfile .beryl/lock.json leaf-symlink
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
  LOCK_MANAGED_DIGESTS="$(lock_array_field "$EXISTING_LOCK" managedPathDigests)"
  if grep -q '"managedPathsVersion"[[:space:]]*:[[:space:]]*1' "$EXISTING_LOCK" && [ -z "$OLD_MANAGED_PATHS" ]; then
    fail "invalid existing lockfile: managedPathsVersion requires managedPaths"
  fi
  if [ -z "$OLD_MANAGED_PATHS" ]; then
    LEGACY_LOCK="1"
    printf "beryl: update is migrating a legacy lockfile with conservative managed-path ownership\n"
  fi
  if [ "$LEGACY_LOCK" = "0" ]; then
    grep -q '"managedPathDigestsVersion"[[:space:]]*:[[:space:]]*1' "$EXISTING_LOCK" || \
      fail "invalid existing lockfile: missing managedPathDigestsVersion"
    [ -n "$LOCK_MANAGED_DIGESTS" ] || fail "invalid existing lockfile: managedPathDigests is empty"
  fi
  LOCK_SOURCE_REF="$(lock_string_field "$EXISTING_LOCK" sourceRef)"
  [ -n "$LOCK_SOURCE_REF" ] || fail "invalid existing lockfile: sourceRef is empty"
  LOCK_EXPECTED_SOURCE_SHA256="$(lock_string_field "$EXISTING_LOCK" expectedSourceSha256)"
  LOCK_ROOT_CONFLICT="$(lock_string_field "$EXISTING_LOCK" rootConflictPolicy)"
  [ -n "$LOCK_ROOT_CONFLICT" ] || LOCK_ROOT_CONFLICT="fail"
  case "$LOCK_ROOT_CONFLICT" in
    fail|overwrite|skip) ;;
    *) fail "invalid existing lockfile: rootConflictPolicy" ;;
  esac
  LOCK_ROOT_CONFLICT_DECISIONS="$(lock_array_field "$EXISTING_LOCK" rootConflictDecisions)"
  LOCK_PRESERVED_ROOT_DIGESTS="$(lock_array_field "$EXISTING_LOCK" preservedRootContractDigests)"
  validate_existing_preserved_root_contracts
  LOCK_HOOK_CONFLICT="$(lock_string_field "$EXISTING_LOCK" hookConflictPolicy)"
  [ -n "$LOCK_HOOK_CONFLICT" ] || LOCK_HOOK_CONFLICT="fail"
  case "$LOCK_HOOK_CONFLICT" in
    fail|preserve|replace) ;;
    *) fail "invalid existing lockfile: hookConflictPolicy" ;;
  esac
  LOCK_GITHOOKS_ENABLED="$(lock_boolean_field "$EXISTING_LOCK" githooksEnabled)"
  [ -n "$LOCK_GITHOOKS_ENABLED" ] || LOCK_GITHOOKS_ENABLED="false"
  LOCK_PREVIOUS_HOOKS_PATH_PRESENT="$(lock_boolean_field "$EXISTING_LOCK" previousHooksPathPresent)"
  [ -n "$LOCK_PREVIOUS_HOOKS_PATH_PRESENT" ] || LOCK_PREVIOUS_HOOKS_PATH_PRESENT="false"
  LOCK_PREVIOUS_HOOKS_PATH="$(lock_string_field "$EXISTING_LOCK" previousHooksPath)"
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
    old_digest="$(update_lock_digest_for_path "$old_rel")"
    if ! lock_path_is_selected "$old_rel" "$LOCK_COMPONENTS"; then
      # A digest changes the threat model. A path without one is merely an
      # unowned ledger entry; a valid digest is an attempt to turn lock state
      # into deletion authority outside the historical component surface.
      if [ -n "$old_digest" ] && valid_sha256 "$old_digest"; then
        update_fail validate lockfile "$old_rel" path-not-selected-by-historical-manifest
      fi
      update_fail validate lockfile "$old_rel" unowned-managed-path
    fi
    [ -n "$old_digest" ] && valid_sha256 "$old_digest" || \
      update_fail validate lockfile "$old_rel" missing-or-invalid-managed-digest
    [ "$(printf '%s\n' "$LOCK_MANAGED_DIGESTS" | sed -n "s#^${old_rel}:##p" | wc -l | tr -d ' ')" = "1" ] || \
      update_fail validate lockfile "$old_rel" duplicate-managed-digest
    validated_old_paths="${validated_old_paths}
${old_rel}"
  done
  for old_digest_entry in $LOCK_MANAGED_DIGESTS; do
    old_digest_path="${old_digest_entry%%:*}"
    old_digest_value="${old_digest_entry#*:}"
    [ "$old_digest_path" != "$old_digest_entry" ] && valid_sha256 "$old_digest_value" || \
      update_fail validate lockfile "$old_digest_entry" malformed-managed-digest
    list_has "$OLD_MANAGED_PATHS" "$old_digest_path" || \
      update_fail validate lockfile "$old_digest_path" digest-without-managed-path
  done
}

# Lock selections are state, but still have to describe a real, closed
# manifest selection.  This checks the syntax-free parser output against the
# staged manifest before any lock ledger can participate in a lifecycle.
lock_component_sets_equal() {
  lock_set_left="$1"
  lock_set_right="$2"
  for lock_component in $lock_set_left; do list_has "$lock_set_right" "$lock_component" || return 1; done
  for lock_component in $lock_set_right; do list_has "$lock_set_left" "$lock_component" || return 1; done
  return 0
}

validate_lock_selection() {
  lock_selection_label="$1"
  lock_selection_requested="$2"
  lock_selection_resolved="$3"
  [ -n "$lock_selection_requested" ] || fail "$lock_selection_label: requestedComponents is empty"
  [ -n "$lock_selection_resolved" ] || fail "$lock_selection_label: components is empty"
  lock_selection_seen=""
  for lock_component in $lock_selection_requested; do
    [ -n "$(manifest_line component "$lock_component")" ] || \
      fail "$lock_selection_label: unknown requested component: $lock_component"
    list_has "$lock_selection_seen" "$lock_component" && \
      fail "$lock_selection_label: duplicate requested component: $lock_component"
    lock_selection_seen="${lock_selection_seen}
${lock_component}"
  done
  lock_selection_expected="$lock_selection_requested"
  lock_selection_changed=1
  while [ "$lock_selection_changed" = "1" ]; do
    lock_selection_changed=0
    for lock_component in $lock_selection_expected; do
      for lock_dependency in $(component_field "$lock_component" requires); do
        if ! list_has "$lock_selection_expected" "$lock_dependency"; then
          lock_selection_expected="${lock_selection_expected}
${lock_dependency}"
          lock_selection_changed=1
        fi
      done
    done
  done
  lock_selection_canonical=""
  for lock_component in $(component_names); do
    if list_has "$lock_selection_expected" "$lock_component"; then
      lock_selection_canonical="${lock_selection_canonical}
${lock_component}"
    fi
  done
  lock_selection_canonical="$(printf '%s\n' "$lock_selection_canonical" | sed '/^$/d')"
  lock_selection_seen=""
  for lock_component in $lock_selection_resolved; do
    [ -n "$(manifest_line component "$lock_component")" ] || \
      fail "$lock_selection_label: unknown resolved component: $lock_component"
    list_has "$lock_selection_seen" "$lock_component" && \
      fail "$lock_selection_label: duplicate resolved component: $lock_component"
    lock_selection_seen="${lock_selection_seen}
${lock_component}"
  done
  lock_component_sets_equal "$lock_selection_canonical" "$lock_selection_resolved" || \
    fail "$lock_selection_label: resolved components do not match requested dependency closure"
}

lock_path_is_selected() {
  lock_path="$1"
  lock_path_components="$2"
  for lock_component in $lock_path_components; do
    for lock_base in $(component_field "$lock_component" paths) $(component_field "$lock_component" rootPaths); do
      case "$lock_base" in
        */) case "$lock_path" in "$lock_base"*) return 0 ;; esac ;;
        *) [ "$lock_path" = "$lock_base" ] && return 0 ;;
      esac
    done
  done
  return 1
}

validate_lock_managed_surface() {
  lock_surface_label="$1"
  lock_surface_paths="$2"
  lock_surface_components="$3"
  for lock_path in $lock_surface_paths; do
    is_preserved_update_path "$lock_path" && \
      fail "$lock_surface_label: target-owned preserved path is managed: $lock_path"
    lock_path_is_selected "$lock_path" "$lock_surface_components" || \
      fail "$lock_surface_label: managed path is outside selected surface: $lock_path"
  done
}

stage_local_paths() {
  STAGE_DIR="$TMP_DIR/stage"
  set_update_context stage source-tree "$SOURCE_DIR"
  mkdir -p "$STAGE_DIR" || fail "could not create staging directory"
  git -C "$SOURCE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    fail "local --source-dir must be a Git checkout so only tracked release files are staged"
  : >"$TMP_DIR/local-source-files" || fail "could not create local source file list"
  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    src="${SOURCE_DIR%/}/$rel"
    [ -e "$src" ] || [ -L "$src" ] || fail "source path missing: $rel"
    case "$rel" in
      */) git -C "$SOURCE_DIR" ls-files -- "$rel" ;;
      *) git -C "$SOURCE_DIR" ls-files --error-unmatch -- "$rel" ;;
    esac >>"$TMP_DIR/local-source-files" || fail "source path is not tracked: $rel"
  done
  sort -u "$TMP_DIR/local-source-files" >"$TMP_DIR/local-source-files.unique" || \
    fail "could not normalize local source file list"
  while IFS= read -r tracked_rel; do
    [ -n "$tracked_rel" ] || continue
    validate_install_path "$tracked_rel"
    tracked_src="$SOURCE_DIR/$tracked_rel"
    [ -f "$tracked_src" ] && [ ! -L "$tracked_src" ] || \
      fail "tracked source file missing or is a symlink: $tracked_rel"
    mkdir -p "$STAGE_DIR/$(dirname "$tracked_rel")" || fail "could not create staging parent: $tracked_rel"
    cp -p "$tracked_src" "$STAGE_DIR/$tracked_rel" || fail "could not stage source path: $tracked_rel"
  done <"$TMP_DIR/local-source-files.unique"
  [ -s "$TMP_DIR/local-source-files.unique" ] || fail "local source contained no tracked install files"
}

add_root_conflict_decision() {
  decision_path="$1"
  decision="$2"
  decision_value="${decision}:${decision_path}"
  list_has "$ROOT_CONFLICT_DECISIONS" "$decision_value" || \
    ROOT_CONFLICT_DECISIONS="${ROOT_CONFLICT_DECISIONS}
${decision_value}"
}

stage_remote_paths() {
  archive="$REMOTE_ARCHIVE"
  STAGE_DIR="$TMP_DIR/stage"
  set_update_context stage archive "$ARCHIVE_URL"
  mkdir -p "$STAGE_DIR" || fail "could not create staging directory"
  [ -f "$archive" ] && [ -n "$REMOTE_ARCHIVE_PREFIX" ] || \
    fail "verified remote archive was not prepared"

  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    tar -xzf "$archive" -C "$STAGE_DIR" --strip-components=1 "${REMOTE_ARCHIVE_PREFIX}/${rel%/}" 2>/dev/null || \
      tar -xzf "$archive" -C "$STAGE_DIR" --strip-components=1 "${REMOTE_ARCHIVE_PREFIX}/${rel}" 2>/dev/null || \
      fail "archive path missing: $rel"
  done
}

stage_managed_paths() {
  NEW_MANAGED_PATHS=""
  : >"$TMP_DIR/staged-paths" || fail "could not create staged path ledger"
  for rel in $INSTALL_PATHS; do
    set_update_context stage "$(component_for_path "$rel")" "$rel"
    [ -e "$STAGE_DIR/$rel" ] || [ -L "$STAGE_DIR/$rel" ] || fail "staged path missing: $rel"
    if find "$STAGE_DIR/$rel" -type l -print -quit | grep -q .; then
      fail "staged source contains unsupported symlink: $rel"
    fi
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
    .gitignore \
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
  if [ -L "$destination_leaf" ]; then
    update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" leaf-symlink
  fi
  if [ -d "$destination_leaf" ] && [ ! -L "$destination_leaf" ]; then
    update_fail "$UPDATE_PHASE" "$destination_component" "$destination_rel" leaf-is-directory
  fi
}

# The target is attacker-controlled input on a first install.  Do not use
# mkdir -p or cd on it until its nearest existing parent has been resolved
# physically and every existing lexical ancestor has been shown not to be a
# symlink.  A non-existent suffix is then safe to create below that parent.
resolve_target_dir() {
  requested_target="$1"
  [ -n "$requested_target" ] || fail "--target must not be empty"
  case "$requested_target" in
    /*) target_candidate="$requested_target" ;;
    *) target_candidate="$(pwd -P)/$requested_target" ;;
  esac
  case "$target_candidate" in
    *'/../'*|*/..|../*|..)
      fail "--target must not contain ..: $requested_target"
      ;;
  esac

  # Check every lexical path component, including an existing target reached
  # through an intermediate symlink.  Checking only the final path would let
  # `target-link/existing-target` resolve outside the selected repository.
  target_remaining="${target_candidate#/}"
  target_walk="/"
  while [ -n "$target_remaining" ]; do
    target_segment="${target_remaining%%/*}"
    if [ "$target_remaining" = "$target_segment" ]; then
      target_remaining=""
    else
      target_remaining="${target_remaining#*/}"
    fi
    [ -n "$target_segment" ] || continue
    target_walk="${target_walk%/}/$target_segment"
    [ ! -L "$target_walk" ] || fail "target or ancestor is a symlink: $target_walk"
    if [ -e "$target_walk" ] && [ ! -d "$target_walk" ]; then
      fail "target or ancestor is not a directory: $target_walk"
    fi
  done

  target_suffix=""
  target_existing="$target_candidate"
  while [ ! -e "$target_existing" ] && [ ! -L "$target_existing" ]; do
    target_base="$(basename "$target_existing")"
    if [ -n "$target_suffix" ]; then
      target_suffix="$target_base/$target_suffix"
    else
      target_suffix="$target_base"
    fi
    target_parent="$(dirname "$target_existing")"
    [ "$target_parent" != "$target_existing" ] || fail "could not resolve target parent: $requested_target"
    target_existing="$target_parent"
  done

  [ ! -L "$target_existing" ] || fail "target or ancestor is a symlink: $target_existing"
  [ -d "$target_existing" ] || fail "target or ancestor is not a directory: $target_existing"
  target_physical="$(cd "$target_existing" && pwd -P)" || fail "could not resolve target parent: $requested_target"

  if [ -n "$target_suffix" ]; then
    TARGET_DIR="$target_physical/$target_suffix"
    INITIAL_TARGET_EXISTED="0"
  else
    TARGET_DIR="$target_physical"
    INITIAL_TARGET_EXISTED="1"
  fi
}

initial_destination_safe() {
  destination_rel="$1"
  destination_parent_rel="$(dirname "$destination_rel")"
  destination_parent="$TARGET_DIR"

  if [ "$destination_parent_rel" != "." ]; then
    for destination_segment in $(printf '%s' "$destination_parent_rel" | tr '/' ' '); do
      destination_parent="$destination_parent/$destination_segment"
      [ ! -L "$destination_parent" ] || return 1
      if [ -e "$destination_parent" ] && [ ! -d "$destination_parent" ]; then
        return 1
      fi
      if [ -d "$destination_parent" ]; then
        destination_physical="$(cd "$destination_parent" && pwd -P)" || return 1
        case "$destination_physical" in
          "$TARGET_DIR"|"$TARGET_DIR"/*) ;;
          *) return 1 ;;
        esac
      fi
    done
  fi

  destination_leaf="$TARGET_DIR/$destination_rel"
  [ ! -L "$destination_leaf" ] || return 1
  [ ! -d "$destination_leaf" ] || return 1
  return 0
}

# A lock is the last transaction write, so its candidate must live beside the
# final lock.  mktemp creates the leaf exclusively (rather than trusting a
# predictable PID name) and the lexical/physical checks keep its parent inside
# the selected target.  Callers remove only the exact returned candidate.
create_target_lock_tmp() {
  target_lock_dir="$TARGET_DIR/.beryl"
  [ ! -L "$target_lock_dir" ] && [ -d "$target_lock_dir" ] || return 1
  target_lock_physical="$(cd "$target_lock_dir" && pwd -P)" || return 1
  [ "$target_lock_physical" = "$TARGET_DIR/.beryl" ] || return 1
  target_lock_tmp="$(umask 077; mktemp "$target_lock_dir/.lock.json.XXXXXX")" || return 1
  [ -f "$target_lock_tmp" ] && [ ! -L "$target_lock_tmp" ] || {
    rm -f "$target_lock_tmp" 2>/dev/null || true
    return 1
  }
  printf '%s' "$target_lock_tmp"
}

# Lifecycle operations can stage independently, but only one may mutate a
# target at a time. The target-local directory is atomically created and lives
# beside .beryl so an initial install can acquire it before creating managed
# state. Cleanup is deliberately limited to the exact empty directory.
acquire_lifecycle_lock() {
  if [ ! -e "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
    mkdir "$TARGET_DIR" || fail "could not create lifecycle target directory"
    LIFECYCLE_CREATED_TARGET="1"
  fi
  [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ] || \
    fail "lifecycle target must be a non-symlink directory"
  lifecycle_target_physical="$(cd "$TARGET_DIR" && pwd -P)" || \
    fail "could not resolve lifecycle target directory"
  [ "$lifecycle_target_physical" = "$TARGET_DIR" ] || \
    fail "lifecycle target resolved outside the selected target"
  if [ "${INITIAL_TARGET_EXISTED:-1}" = "1" ]; then
    LIFECYCLE_TARGET_MTIME_FILE="$TMP_DIR/lifecycle-target-mtime"
    touch -r "$TARGET_DIR" "$LIFECYCLE_TARGET_MTIME_FILE" || \
      fail "could not snapshot lifecycle target metadata"
  fi

  LIFECYCLE_LOCK_DIR="$TARGET_DIR/.beryl.lifecycle.lock"
  [ ! -L "$LIFECYCLE_LOCK_DIR" ] || \
    fail "lifecycle lock path must not be a symlink"
  if ! mkdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null; then
    fail "another Beryl lifecycle operation is already running for this target"
  fi
  [ -d "$LIFECYCLE_LOCK_DIR" ] && [ ! -L "$LIFECYCLE_LOCK_DIR" ] || \
    fail "could not acquire a safe lifecycle lock"
  LIFECYCLE_LOCK_HELD="1"

  # Test-only delay used to prove same-target refusal without slowing normal
  # lifecycle runs.
  lifecycle_hold_seconds="${BERYL_LIFECYCLE_TEST_HOLD_LOCK_SECONDS:-0}"
  case "$lifecycle_hold_seconds" in
    0|"") ;;
    *[!0-9]*) fail "BERYL_LIFECYCLE_TEST_HOLD_LOCK_SECONDS must be a non-negative integer" ;;
    *) sleep "$lifecycle_hold_seconds" ;;
  esac
  lifecycle_hold_file="${BERYL_LIFECYCLE_TEST_HOLD_LOCK_FILE:-}"
  while [ -n "$lifecycle_hold_file" ] && \
        { [ -e "$lifecycle_hold_file" ] || [ -L "$lifecycle_hold_file" ]; }; do
    sleep 1
  done
}

release_lifecycle_lock() {
  [ "${LIFECYCLE_LOCK_HELD:-0}" = "1" ] || return 0
  if [ -d "$LIFECYCLE_LOCK_DIR" ] && [ ! -L "$LIFECYCLE_LOCK_DIR" ]; then
    rmdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null || \
      printf 'beryl: warning: could not safely remove lifecycle lock: %s\n' "$LIFECYCLE_LOCK_DIR" >&2
  elif [ -e "$LIFECYCLE_LOCK_DIR" ] || [ -L "$LIFECYCLE_LOCK_DIR" ]; then
    printf 'beryl: warning: lifecycle lock changed unexpectedly; refusing cleanup: %s\n' "$LIFECYCLE_LOCK_DIR" >&2
  fi
  LIFECYCLE_LOCK_HELD="0"
  if [ "${LIFECYCLE_CREATED_TARGET:-0}" = "1" ] && [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
    # Initial targets created solely for a rejected preflight are safe to
    # remove only when empty. Never recursively remove a user-visible target.
    rmdir "$TARGET_DIR" 2>/dev/null || true
  elif [ "${LIFECYCLE_COMMITTED:-0}" = "0" ] && \
       [ -n "${LIFECYCLE_TARGET_MTIME_FILE:-}" ] && [ -d "$TARGET_DIR" ] && [ ! -L "$TARGET_DIR" ]; then
    # Lock acquisition itself changes the parent directory timestamp. Failed
    # preflight/rollback paths must remain observationally zero-mutation.
    touch -r "$LIFECYCLE_TARGET_MTIME_FILE" "$TARGET_DIR" 2>/dev/null || true
  fi
}

validate_initial_destination_path() {
  destination_rel="$1"
  destination_component="$2"
  initial_destination_safe "$destination_rel" || \
    fail "unsafe initial-install destination (symlink, directory, or outside target): $destination_component $destination_rel"
}

preflight_required_runtimes() {
  command -v bash >/dev/null 2>&1 || fail "required runtime missing: bash"
  command -v mktemp >/dev/null 2>&1 || fail "required runtime missing: mktemp"
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || \
    fail "required runtime missing: sha256sum or shasum"
}

init_tmp_dir() {
  [ -z "${TMP_DIR:-}" ] || return 0
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-install.XXXXXX")" || fail "could not create private installer temporary directory"
}

preflight_initial_install() {
  INSTALL_PHASE="preflight"
  INSTALL_PATH=".beryl"
  [ "$INITIAL_TARGET_EXISTED" = "0" ] || {
    [ ! -e "$TARGET_DIR/.beryl" ] && [ ! -L "$TARGET_DIR/.beryl" ] || \
      fail "existing unlocked .beryl directory refused; use the lifecycle adoption command when available"
  }

  MUTATION_PATHS=""
  for initial_rel in $NEW_MANAGED_PATHS; do
    INSTALL_PATH="$initial_rel"
    validate_initial_destination_path "$initial_rel" "$(component_for_path "$initial_rel")"
    add_mutation_path "$initial_rel"
    case "$initial_rel" in
      .beryl/*) ;;
      *)
        initial_dst="$TARGET_DIR/$initial_rel"
        if [ -e "$initial_dst" ] && ! cmp -s "$STAGE_DIR/$initial_rel" "$initial_dst" 2>/dev/null; then
          case "$ROOT_CONFLICT" in
            fail) fail "root file conflict: $initial_rel (use --root-conflict overwrite or skip)" ;;
            skip|overwrite) ;;
          esac
        fi
        ;;
    esac
  done
  add_mutation_path .beryl/lock.json
  add_hook_mutation_paths
  for initial_rel in $MUTATION_PATHS; do
    INSTALL_PATH="$initial_rel"
    validate_initial_destination_path "$initial_rel" "$(component_for_path "$initial_rel")"
  done
}

snapshot_initial_path() {
  snapshot_rel="$1"
  list_has "$SNAPSHOT_PATHS" "$snapshot_rel" && return 0
  SNAPSHOT_PATHS="${SNAPSHOT_PATHS}
${snapshot_rel}"
  snapshot_target="$TARGET_DIR/$snapshot_rel"
  if [ -e "$snapshot_target" ] || [ -L "$snapshot_target" ]; then
    mkdir -p "$ROLLBACK_DIR/files/$(dirname "$snapshot_rel")" || fail "could not snapshot install path: $snapshot_rel"
    cp -pR "$snapshot_target" "$ROLLBACK_DIR/files/$snapshot_rel" || fail "could not snapshot install path: $snapshot_rel"
  else
    mkdir -p "$ROLLBACK_DIR/missing/$(dirname "$snapshot_rel")" || fail "could not snapshot install path: $snapshot_rel"
    : >"$ROLLBACK_DIR/missing/$snapshot_rel"
  fi
}

snapshot_initial_directory_metadata() {
  directory_metadata_rel="$1"
  list_has "$SNAPSHOT_DIRECTORY_PATHS" "$directory_metadata_rel" && return 0
  metadata_target="$TARGET_DIR"
  if [ "$directory_metadata_rel" != "." ]; then
    metadata_target="$TARGET_DIR/$directory_metadata_rel"
  fi
  [ -d "$metadata_target" ] || return 0
  SNAPSHOT_DIRECTORY_PATHS="${SNAPSHOT_DIRECTORY_PATHS}
${directory_metadata_rel}"
  metadata_snapshot_dir="$ROLLBACK_DIR/directory-mtimes/$directory_metadata_rel"
  mkdir -p "$metadata_snapshot_dir" || fail "could not snapshot install directory metadata"
  touch -r "$metadata_target" "$metadata_snapshot_dir/.mtime" || \
    fail "could not snapshot install directory metadata"
}

snapshot_initial_parent_metadata() {
  parent_metadata_input="$1"
  snapshot_initial_directory_metadata .
  metadata_parent_rel="$(dirname "$parent_metadata_input")"
  [ "$metadata_parent_rel" = "." ] && return 0
  metadata_path=""
  for metadata_segment in $(printf '%s' "$metadata_parent_rel" | tr '/' ' '); do
    if [ -n "$metadata_path" ]; then
      metadata_path="$metadata_path/$metadata_segment"
    else
      metadata_path="$metadata_segment"
    fi
    snapshot_initial_directory_metadata "$metadata_path"
  done
}

snapshot_initial_install() {
  ROLLBACK_DIR="$TMP_DIR/rollback"
  mkdir -p "$ROLLBACK_DIR/files" "$ROLLBACK_DIR/missing" || fail "could not create install rollback directory"
  SNAPSHOT_PATHS=""
  SNAPSHOT_DIRECTORY_PATHS=""
  for initial_rel in $MUTATION_PATHS; do
    snapshot_initial_parent_metadata "$initial_rel"
    snapshot_initial_path "$initial_rel"
  done
  capture_githooks_config
  INITIAL_TRANSACTION_READY="1"
  ROLLBACK_READY="1"
}

prune_empty_initial_parent() {
  prune_rel="$(dirname "$1")"
  while [ "$prune_rel" != "." ] && [ "$prune_rel" != "/" ]; do
    rmdir "$TARGET_DIR/$prune_rel" 2>/dev/null || break
    prune_rel="$(dirname "$prune_rel")"
  done
}

rollback_initial_install() {
  [ "${INITIAL_TRANSACTION_READY:-0}" = "1" ] || { printf 'not-started'; return 0; }
  rollback_result="ok"
  if [ "${INITIAL_TARGET_EXISTED:-1}" = "0" ]; then
    if [ -L "$TARGET_DIR" ] || ! rm -rf "$TARGET_DIR" 2>/dev/null; then
      rollback_result="failed"
    fi
  else
    for snapshot_rel in $SNAPSHOT_PATHS; do
      rollback_target="$TARGET_DIR/$snapshot_rel"
      if [ -f "$ROLLBACK_DIR/missing/$snapshot_rel" ]; then
        rm -f "$rollback_target" 2>/dev/null || rollback_result="failed"
        prune_empty_initial_parent "$snapshot_rel"
      else
        rm -f "$rollback_target" 2>/dev/null || rollback_result="failed"
        mkdir -p "$(dirname "$rollback_target")" || rollback_result="failed"
        cp -pR "$ROLLBACK_DIR/files/$snapshot_rel" "$rollback_target" 2>/dev/null || rollback_result="failed"
      fi
    done
    for snapshot_directory_rel in $SNAPSHOT_DIRECTORY_PATHS; do
      if [ "$snapshot_directory_rel" = "." ]; then
        snapshot_directory_target="$TARGET_DIR"
      else
        snapshot_directory_target="$TARGET_DIR/$snapshot_directory_rel"
      fi
      [ -d "$snapshot_directory_target" ] && \
        touch -r "$ROLLBACK_DIR/directory-mtimes/$snapshot_directory_rel/.mtime" "$snapshot_directory_target" \
          2>/dev/null || rollback_result="failed"
    done
  fi
  if [ "${GIT_HOOKS_CONFIG_READY:-0}" = "1" ]; then
    if [ "${GIT_HOOKS_CONFIG_PRESENT:-0}" = "1" ]; then
      git -C "$TARGET_DIR" config --local core.hooksPath "$(cat "$ROLLBACK_DIR/git-hooks-path")" \
        2>/dev/null || rollback_result="failed"
    else
      git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
    fi
  fi
  printf '%s' "$rollback_result"
}

capture_githooks_config() {
  [ "$GIT_HOOKS_CONFIG_READY" = "0" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  set_update_context snapshot githooks .git/config
  if ! git -C "$TARGET_DIR" config --local --list >/dev/null 2>&1; then
    if [ "$UPDATE_MODE" = "1" ]; then
      update_fail snapshot githooks .git/config read-config
    fi
    fail "could not read Git hook configuration"
  fi
  GIT_HOOKS_CONFIG_READY="1"
  if git -C "$TARGET_DIR" config --local --get core.hooksPath >"$ROLLBACK_DIR/git-hooks-path"; then
    GIT_HOOKS_CONFIG_PRESENT="1"
  else
    GIT_HOOKS_CONFIG_PRESENT="0"
  fi
  if [ "$GITHOOKS_REMOVED" = "1" ]; then
    GIT_HOOKS_PREVIOUS_PATH_PRESENT="$LOCK_PREVIOUS_HOOKS_PATH_PRESENT"
    GIT_HOOKS_PREVIOUS_PATH="$LOCK_PREVIOUS_HOOKS_PATH"
  else
    GIT_HOOKS_PREVIOUS_PATH_PRESENT="$PREFLIGHT_HOOKS_PATH_PRESENT"
    GIT_HOOKS_PREVIOUS_PATH="$PREFLIGHT_HOOKS_PATH"
  fi
}

preflight_githooks_config() {
  [ "$ENABLE_GITHOOKS" = "1" ] || [ "$GITHOOKS_REMOVED" = "1" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  # The rollback directory is initialized immediately after preflight.  Store
  # the observed value now and capture it there before mutation.
  if git -C "$TARGET_DIR" config --get core.hooksPath >"$TMP_DIR/preflight-hooks-path"; then
    PREFLIGHT_HOOKS_PATH_PRESENT="true"
    PREFLIGHT_HOOKS_PATH="$(cat "$TMP_DIR/preflight-hooks-path")"
    if [ "$GITHOOKS_REMOVED" = "1" ]; then
      if [ "$PREFLIGHT_HOOKS_PATH" = ".beryl/githooks" ] && [ "$LOCK_GITHOOKS_ENABLED" = "true" ]; then
        GIT_HOOKS_RESTORE="1"
      fi
      GIT_HOOKS_CONFIGURE="0"
      GIT_HOOKS_ENABLED="false"
      return 0
    fi
    if [ "$PREFLIGHT_HOOKS_PATH" = ".beryl/githooks" ]; then
      GIT_HOOKS_CONFIGURE="1"
      GIT_HOOKS_ENABLED="true"
    else
      case "$HOOK_CONFLICT" in
        fail)
          fail "existing core.hooksPath conflict: $PREFLIGHT_HOOKS_PATH (use --hook-conflict preserve or replace)"
          ;;
        preserve)
          GIT_HOOKS_CONFIGURE="0"
          GIT_HOOKS_ENABLED="false"
          ;;
        replace)
          GIT_HOOKS_CONFIGURE="1"
          GIT_HOOKS_ENABLED="true"
          ;;
      esac
    fi
  else
    PREFLIGHT_HOOKS_PATH_PRESENT="false"
    PREFLIGHT_HOOKS_PATH=""
    if [ "$GITHOOKS_REMOVED" = "1" ]; then
      GIT_HOOKS_CONFIGURE="0"
      GIT_HOOKS_ENABLED="false"
      return 0
    fi
    GIT_HOOKS_CONFIGURE="1"
    GIT_HOOKS_ENABLED="true"
  fi
}

restore_removed_githooks() {
  [ "$GIT_HOOKS_RESTORE" = "1" ] || return 0
  if [ "$LOCK_PREVIOUS_HOOKS_PATH_PRESENT" = "true" ]; then
    git -C "$TARGET_DIR" config --local core.hooksPath "$LOCK_PREVIOUS_HOOKS_PATH" || {
      [ "$UPDATE_MODE" = "1" ] && update_fail hook githooks .git/config restore-previous-hooks
      fail "could not restore previous Git hook configuration"
    }
  else
    git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
  fi
  GIT_HOOKS_ENABLED="false"
  printf 'beryl: restored prior core.hooksPath after githooks component removal\n'
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
  SNAPSHOT_DIRECTORY_PATHS=""
  MUTATION_PATHS=""
  for snapshot_rel in $NEW_MANAGED_PATHS $OLD_MANAGED_PATHS; do
    is_preserved_update_path "$snapshot_rel" || add_mutation_path "$snapshot_rel"
  done
  add_mutation_path .beryl/lock.json
  set_update_context snapshot hooks .beryl/agent
  add_hook_mutation_paths
  for snapshot_rel in $MUTATION_PATHS; do
    snapshot_initial_parent_metadata "$snapshot_rel"
    snapshot_path "$snapshot_rel"
  done
  capture_githooks_config
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
  for snapshot_directory_rel in $SNAPSHOT_DIRECTORY_PATHS; do
    if [ "$snapshot_directory_rel" = "." ]; then
      snapshot_directory_target="$TARGET_DIR"
    else
      snapshot_directory_target="$TARGET_DIR/$snapshot_directory_rel"
    fi
    [ -d "$snapshot_directory_target" ] && \
      touch -r "$ROLLBACK_DIR/directory-mtimes/$snapshot_directory_rel/.mtime" "$snapshot_directory_target" \
        2>/dev/null || rollback_result="failed"
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
    backup_cleanup_parent="$TARGET_DIR/.beryl/.updates"
    case "$BACKUP_DIR" in "$backup_cleanup_parent"/.backup.*) ;; *) rollback_result="failed"; BACKUP_DIR="" ;; esac
    if [ -n "$BACKUP_DIR" ]; then
      if [ -L "$backup_cleanup_parent" ] || [ -L "$BACKUP_DIR" ]; then
        rollback_result="failed"
      elif [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR" 2>/dev/null || rollback_result="failed"
      elif [ -e "$BACKUP_DIR" ]; then
        rollback_result="failed"
      fi
    fi
  fi
  if [ "${UPDATE_BACKUP_PARENT_CREATED:-0}" = "1" ]; then
    rmdir "$TARGET_DIR/.beryl/.updates" 2>/dev/null || rollback_result="failed"
  elif [ -f "$ROLLBACK_DIR/directory-mtimes/.beryl/.updates/.mtime" ] && \
       [ -d "$TARGET_DIR/.beryl/.updates" ] && [ ! -L "$TARGET_DIR/.beryl/.updates" ]; then
    touch -r "$ROLLBACK_DIR/directory-mtimes/.beryl/.updates/.mtime" "$TARGET_DIR/.beryl/.updates" \
      2>/dev/null || rollback_result="failed"
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
              add_root_conflict_decision "$apply_rel" skip
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
  else
    validate_initial_destination_path "$apply_rel" "$apply_component"
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
  # A prior lock is state, not deletion authority. A successful update never
  # deletes a path solely because it disappeared from the new selection.
  for removed_rel in $OLD_MANAGED_PATHS; do
    list_has "$NEW_MANAGED_PATHS" "$removed_rel" && continue
    is_preserved_update_path "$removed_rel" && continue
    printf 'beryl: preserved ambiguous removed path %s\n' "$removed_rel"
    PRESERVED_COUNT=$((PRESERVED_COUNT + 1))
  done
}

update_lock_digest_for_path() {
  update_digest_rel="$1"
  printf '%s\n' "$LOCK_MANAGED_DIGESTS" | sed -n "s#^${update_digest_rel}:##p"
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
            if [ "$GIT_HOOKS_CONFIGURE" = "1" ]; then
              printf "beryl: running post-install hook: git config core.hooksPath .beryl/githooks\n"
              if ! git -C "$TARGET_DIR" config --local core.hooksPath .beryl/githooks; then
                [ "$UPDATE_MODE" = "1" ] && update_fail hook "$component" enable-githooks failed
                fail "post-install hook failed: enable-githooks"
              fi
            else
              printf "beryl: preserved existing core.hooksPath by --hook-conflict preserve\n"
            fi
          else
            printf "beryl: skipped githook enablement (pass --enable-githooks inside a Git repo)\n"
          fi
          ;;
      esac
    done
  done
}

run_agent_bootstrap_after_install() {
  [ -x "$TARGET_DIR/.beryl/agent/scripts/bootstrap-agent-context.sh" ] || return 0
  printf "beryl: running agent bootstrap: .beryl/agent/scripts/bootstrap-agent-context.sh\n"
  (cd "$TARGET_DIR" && \
    BERYL_AGENT_FALLBACK="$AGENT_FALLBACK" \
    BERYL_AGENT_RUNNER="${AGENT_RUNNER}" \
    BERYL_AGENT_COMMAND_TEMPLATE="${AGENT_COMMAND_TEMPLATE}" \
    BERYL_AGENT_POLICY="$AGENT_POLICY" \
    BERYL_BOOTSTRAP_SOURCE_REF="$SOURCE_REF" \
    BERYL_BOOTSTRAP_INSTALLER_VERSION="$INSTALLER_VERSION" \
    BERYL_BOOTSTRAP_PROFILE="${PROFILE}" \
    BERYL_BOOTSTRAP_COMPONENTS="$RESOLVED_COMPONENTS" \
    ./.beryl/agent/scripts/bootstrap-agent-context.sh)
}

run_bootstrap_action() {
  BOOTSTRAP_LOCK="$TARGET_DIR/.beryl/lock.json"
  BOOTSTRAP_SCRIPTS_DIR="$TARGET_DIR/.beryl/agent/scripts"
  BOOTSTRAP_SCRIPT="$BOOTSTRAP_SCRIPTS_DIR/bootstrap-agent-context.sh"
  [ ! -L "$TARGET_DIR/.beryl" ] || fail "bootstrap target .beryl must not be a symlink"
  [ ! -L "$TARGET_DIR/.beryl/agent" ] || fail "bootstrap target .beryl/agent must not be a symlink"
  [ ! -L "$BOOTSTRAP_SCRIPTS_DIR" ] || fail "bootstrap target .beryl/agent/scripts must not be a symlink"
  [ ! -L "$BOOTSTRAP_LOCK" ] || fail "bootstrap target lockfile must not be a symlink"
  [ ! -L "$BOOTSTRAP_SCRIPT" ] || fail "bootstrap target bootstrap script must not be a symlink"
  [ -f "$BOOTSTRAP_LOCK" ] || fail "bootstrap requires an existing lockfile: .beryl/lock.json"
  [ -d "$BOOTSTRAP_SCRIPTS_DIR" ] || fail "bootstrap target is missing scripts directory"
  [ -f "$BOOTSTRAP_SCRIPT" ] && [ -x "$BOOTSTRAP_SCRIPT" ] || \
    fail "bootstrap target is missing executable agent bootstrap script"

  SOURCE_REF="$(sed -n 's/^[[:space:]]*"sourceRef"[[:space:]]*:[[:space:]]*"\([^"]*\)".*$/\1/p' "$BOOTSTRAP_LOCK" | head -n 1)"
  [ -n "$SOURCE_REF" ] || SOURCE_REF="installed"
  PROFILE="locked"
  RESOLVED_COMPONENTS="$(lock_array_field "$BOOTSTRAP_LOCK" components)"

  if run_agent_bootstrap_after_install; then
    printf 'beryl: agent bootstrap complete\n'
    exit 0
  else
    bootstrap_status=$?
  fi
  printf 'beryl: agent bootstrap failed exit=%s; installation remains committed\n' "$bootstrap_status" >&2
  exit 2
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
    if [ "$ENABLE_GITHOOKS" = "1" ] && [ "$GIT_HOOKS_CONFIGURE" = "0" ]; then
      printf "beryl: Beryl githooks were installed but are not active; existing core.hooksPath was preserved.\n"
    elif [ "$GIT_HOOKS_ENABLED" = "true" ]; then
      printf "beryl: Beryl githooks are active through core.hooksPath=.beryl/githooks.\n"
    else
      printf "beryl: if you need the local pre-commit hook, run:\n"
      printf "beryl:   cd %s && git config core.hooksPath .beryl/githooks\n" "$target"
      printf "beryl: required before running this command:\n"
      printf "beryl:   - command must run inside a Git repo (or initialize one first)\n"
      printf "beryl:   - .git/config must be writable by this process\n"
      printf "beryl: common failure modes:\n"
      printf "beryl:   - fatal: not a git repository (run inside a repo)\n"
      printf "beryl:   - fatal: could not lock config file .git/config: Permission denied\n"
    fi
  fi
}

write_lockfile() {
  [ ! -L "$TARGET_DIR/.beryl" ] || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl parent-symlink
    fail "refusing symlinked .beryl lock directory"
  }
  if [ -e "$TARGET_DIR/.beryl" ] && [ ! -d "$TARGET_DIR/.beryl" ]; then
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl parent-not-directory
    fail "could not create .beryl for lockfile"
  fi
  mkdir -p "$TARGET_DIR/.beryl" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl mkdir
    fail "could not create .beryl for lockfile"
  }
  # Keep the final replace in the target filesystem. `mv` from /tmp can
  # degrade to copy-and-unlink across mounts, which is not a lock commit.
  lock_tmp="$(create_target_lock_tmp)" || {
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl create-candidate
    fail "could not create secure lockfile candidate"
  }
  {
    printf "{\n"
    printf "  \"installerVersion\": \"%s\",\n" "$INSTALLER_VERSION"
    printf "  \"sourceRef\": \"%s\",\n" "$SOURCE_REF"
    printf "  \"expectedSourceSha256\": \"%s\",\n" "$EXPECTED_SHA256"
    printf "  \"source\": \"%s\",\n" "$SOURCE_LABEL"
    if [ -n "${BERYL_SIGNED_RELEASE_KEY_ID:-}" ]; then
      printf "  \"releaseTrust\": \"signed-bootstrap\",\n"
      printf "  \"signedReleaseTag\": \"%s\",\n" "$(json_string "$BERYL_SIGNED_RELEASE_TAG")"
      printf "  \"signedReleaseKeyId\": \"%s\",\n" "$(json_string "$BERYL_SIGNED_RELEASE_KEY_ID")"
      printf "  \"signedReleaseIssuedAt\": \"%s\",\n" "$(json_string "$BERYL_SIGNED_RELEASE_ISSUED_AT")"
      printf "  \"signedReleaseExpiresAt\": \"%s\",\n" "$(json_string "$BERYL_SIGNED_RELEASE_EXPIRES_AT")"
    else
      printf "  \"releaseTrust\": \"explicit-digest\",\n"
    fi
    printf "  \"rootConflictPolicy\": \"%s\",\n" "$(json_string "$ROOT_CONFLICT")"
    printf "  \"rootConflictDecisions\": "
    printf "%s\n" "$ROOT_CONFLICT_DECISIONS" | json_array_from_lines
    printf ",\n"
    printf "  \"preservedRootContractDigestsVersion\": 1,\n"
    printf "  \"preservedRootContractDigests\": "
    preserved_root_contract_digest_entries | json_array_from_lines
    printf ",\n"
    printf "  \"hookConflictPolicy\": \"%s\",\n" "$(json_string "$HOOK_CONFLICT")"
    printf "  \"githooksEnabled\": %s,\n" "$GIT_HOOKS_ENABLED"
    printf "  \"previousHooksPathPresent\": %s,\n" "$GIT_HOOKS_PREVIOUS_PATH_PRESENT"
    printf "  \"previousHooksPath\": \"%s\",\n" "$(json_string "$GIT_HOOKS_PREVIOUS_PATH")"
    printf "  \"requestedComponents\": "
    printf "%s\n" "$REQUESTED_COMPONENTS" | json_array_from_lines
    printf ",\n"
    printf "  \"components\": "
    printf "%s\n" "$RESOLVED_COMPONENTS" | json_array_from_lines
    printf ",\n"
    printf "  \"managedPathsVersion\": 1,\n"
    printf "  \"managedPaths\": "
    printf "%s\n" "$FINAL_MANAGED_PATHS" | json_array_from_lines
    printf ",\n"
    printf "  \"managedPathDigestsVersion\": 1,\n"
    printf "  \"managedPathDigests\": "
    managed_digest_entries | json_array_from_lines
    printf "\n}\n"
  } >"$lock_tmp" || {
    rm -f "$lock_tmp" 2>/dev/null || true
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl/lock.json write
    fail "could not write lockfile"
  }
  if ! "$TARGET_DIR/.beryl/agent/scripts/agent-doctor.sh" --lockfile "$lock_tmp"; then
    rm -f "$lock_tmp" 2>/dev/null || true
    fail "installed readiness verification failed against candidate lockfile"
  fi
  mv "$lock_tmp" "$TARGET_DIR/.beryl/lock.json" || {
    rm -f "$lock_tmp" 2>/dev/null || true
    [ "$UPDATE_MODE" = "1" ] && update_fail lock lockfile .beryl/lock.json replace
    fail "could not replace lockfile"
  }
  if ! "$TARGET_DIR/.beryl/agent/scripts/agent-doctor.sh"; then
    fail "installed readiness verification failed after lock commit"
  fi
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
  backup_parent="$TARGET_DIR/.beryl/.updates"
  set_update_context backup backup .beryl/.updates/.backup-candidate
  validate_update_destination_path .beryl/.updates/.backup-candidate backup
  if [ -d "$backup_parent" ]; then
    snapshot_initial_directory_metadata .beryl/.updates
  else
    UPDATE_BACKUP_PARENT_CREATED="1"
  fi
  mkdir "$backup_parent" 2>/dev/null || {
    [ -d "$backup_parent" ] && [ ! -L "$backup_parent" ] || \
      update_fail backup backup .beryl/.updates mkdir
  }
  backup_parent_physical="$(cd "$backup_parent" && pwd -P)" || \
    update_fail backup backup .beryl/.updates unreadable
  [ "$backup_parent_physical" = "$backup_parent" ] || \
    update_fail backup backup .beryl/.updates outside-target
  BACKUP_DIR="$(umask 077; mktemp -d "$backup_parent/.backup.XXXXXX")" || \
    update_fail backup backup .beryl/.updates create-candidate
  [ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ] || \
    update_fail backup backup .beryl/.updates unsafe-candidate
  case "$BACKUP_DIR" in "$backup_parent"/.backup.*) ;; *) update_fail backup backup .beryl/.updates outside-target ;; esac
  backup_rel="${BACKUP_DIR#${TARGET_DIR}/}"
  mkdir "$BACKUP_DIR/files" || update_fail backup backup "$backup_rel" mkdir
  BACKUP_CREATED="1"
  for backup_rel in $SNAPSHOT_PATHS; do
    [ -e "$ROLLBACK_DIR/files/$backup_rel" ] || [ -L "$ROLLBACK_DIR/files/$backup_rel" ] || continue
    mkdir -p "$BACKUP_DIR/files/$(dirname "$backup_rel")" || update_fail backup backup "$backup_rel" mkdir
    cp -pR "$ROLLBACK_DIR/files/$backup_rel" "$BACKUP_DIR/files/$backup_rel" || \
      update_fail backup backup "$backup_rel" copy
  done
  # A retained backup is not a copy of the transaction rollback journal. The
  # journal includes target-owned seed and .gitignore changes so rollback can
  # undo this update, but a later restore may only replay the old managed
  # release surface. Metadata therefore records the prior lock's managed
  # paths, never hook side effects or target-owned context.
  BACKUP_RESTORE_PATHS=""
  for backup_rel in $OLD_MANAGED_PATHS .beryl/lock.json; do
    list_has "$SNAPSHOT_PATHS" "$backup_rel" || continue
    list_has "$BACKUP_RESTORE_PATHS" "$backup_rel" || \
      BACKUP_RESTORE_PATHS="${BACKUP_RESTORE_PATHS}
${backup_rel}"
  done
  BACKUP_RESTORE_PATHS="$(printf '%s\n' "$BACKUP_RESTORE_PATHS" | sed '/^$/d')"
  {
    printf "{\n"
    printf "  \"schemaVersion\": 1,\n"
    printf "  \"backupId\": \"%s\",\n" "$(basename "$BACKUP_DIR")"
    printf "  \"snapshotPaths\": "
    printf "%s\n" "$BACKUP_RESTORE_PATHS" | json_array_from_lines
    printf ",\n"
    printf "  \"missingPaths\": "
    for backup_rel in $BACKUP_RESTORE_PATHS; do
      [ -f "$ROLLBACK_DIR/missing/$backup_rel" ] && printf '%s\n' "$backup_rel"
    done | json_array_from_lines
    printf ",\n"
    printf "  \"replacementManagedPaths\": "
    printf "%s\n" "$FINAL_MANAGED_PATHS" | json_array_from_lines
    printf ",\n"
    if [ "$GIT_HOOKS_CONFIG_READY" = "1" ]; then printf '  "gitHooksCaptured": true,\n'; else printf '  "gitHooksCaptured": false,\n'; fi
    if [ "$GIT_HOOKS_CONFIG_PRESENT" = "1" ]; then printf '  "gitHooksPathPresent": true,\n'; else printf '  "gitHooksPathPresent": false,\n'; fi
    printf "  \"gitHooksPath\": \"%s\"\n" \
      "$( [ "$GIT_HOOKS_CONFIG_PRESENT" = "1" ] && cat "$ROLLBACK_DIR/git-hooks-path" || true )"
    printf "}\n"
  } >"$BACKUP_DIR/metadata.json" || update_fail backup backup "$backup_rel" metadata
  printf 'beryl: update backup %s\n' "${BACKUP_DIR#${TARGET_DIR}/}"
}

# Recovery metadata is hostile state, never authority. Paths are syntax-checked
# here, then separately authorized against a fresh staged release surface.
recovery_validate_path() {
  recovery_rel="$1"
  # Deterministic hooks legitimately snapshot these two target contracts even
  # though neither is a manifest-delivered component path.
  case "$recovery_rel" in
    .gitignore|tests/.manifest.sha256) ;;
    *) validate_install_path "$recovery_rel" ;;
  esac
  case "$recovery_rel" in
    *:*|*'"'*|*'\\'*) fail "recovery path contains an unsupported delimiter: $recovery_rel" ;;
    .beryl/.updates|.beryl/.updates/*) fail "recovery lock may not manage backup storage: $recovery_rel" ;;
  esac
}

recovery_validate_lock() {
  recovery_lock="$1"
  [ ! -L "$TARGET_DIR/.beryl" ] || fail "recovery lock directory must not be a symlink"
  [ -d "$TARGET_DIR/.beryl" ] || fail "recovery requires an existing .beryl directory"
  [ ! -L "$recovery_lock" ] || fail "recovery lockfile must not be a symlink"
  [ -f "$recovery_lock" ] || fail "recovery requires an existing regular lockfile: .beryl/lock.json"
  grep -q '"managedPathsVersion"[[:space:]]*:[[:space:]]*1' "$recovery_lock" || \
    fail "recovery refuses legacy lockfile without managed path ownership proof"
  grep -q '"managedPathDigestsVersion"[[:space:]]*:[[:space:]]*1' "$recovery_lock" || \
    fail "recovery refuses lockfile without managed file digests"
  RECOVERY_MANAGED_PATHS="$(lock_array_field "$recovery_lock" managedPaths)"
  RECOVERY_DIGESTS="$(lock_array_field "$recovery_lock" managedPathDigests)"
  RECOVERY_REQUESTED_COMPONENTS="$(lock_array_field "$recovery_lock" requestedComponents)"
  RECOVERY_LOCK_COMPONENTS="$(lock_array_field "$recovery_lock" components)"
  RECOVERY_LOCK_SOURCE_REF="$(lock_string_field "$recovery_lock" sourceRef)"
  RECOVERY_LOCK_EXPECTED_SOURCE_SHA256="$(lock_string_field "$recovery_lock" expectedSourceSha256)"
  [ -n "$RECOVERY_REQUESTED_COMPONENTS" ] || fail "invalid recovery lockfile: requestedComponents is empty"
  [ -n "$RECOVERY_LOCK_COMPONENTS" ] || fail "invalid recovery lockfile: components is empty"
  [ -n "$RECOVERY_LOCK_SOURCE_REF" ] || fail "invalid recovery lockfile: sourceRef is empty"
  validate_source_ref "$RECOVERY_LOCK_SOURCE_REF"
  LOCK_GITHOOKS_ENABLED="$(lock_boolean_field "$recovery_lock" githooksEnabled)"
  [ -n "$LOCK_GITHOOKS_ENABLED" ] || LOCK_GITHOOKS_ENABLED="false"
  LOCK_PREVIOUS_HOOKS_PATH_PRESENT="$(lock_boolean_field "$recovery_lock" previousHooksPathPresent)"
  [ -n "$LOCK_PREVIOUS_HOOKS_PATH_PRESENT" ] || LOCK_PREVIOUS_HOOKS_PATH_PRESENT="false"
  LOCK_PREVIOUS_HOOKS_PATH="$(lock_string_field "$recovery_lock" previousHooksPath)"
  case "$LOCK_GITHOOKS_ENABLED:$LOCK_PREVIOUS_HOOKS_PATH_PRESENT" in true:true|true:false|false:true|false:false) ;; *) fail "invalid recovery lockfile: hook state" ;; esac
  [ -n "$RECOVERY_MANAGED_PATHS" ] || fail "invalid recovery lockfile: managedPaths is empty"
  [ -n "$RECOVERY_DIGESTS" ] || fail "invalid recovery lockfile: managedPathDigests is empty"
  recovery_seen=""
  for recovery_rel in $RECOVERY_MANAGED_PATHS; do
    list_has "$recovery_seen" "$recovery_rel" && fail "invalid recovery lockfile: duplicate managed path: $recovery_rel"
    recovery_seen="${recovery_seen}\n${recovery_rel}"
    recovery_validate_path "$recovery_rel"
    recovery_digest="$(printf '%s\n' "$RECOVERY_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    [ -n "$recovery_digest" ] || fail "invalid recovery lockfile: missing digest for $recovery_rel"
    valid_sha256 "$recovery_digest" || fail "invalid recovery lockfile: invalid digest for $recovery_rel"
    [ "$(printf '%s\n' "$RECOVERY_DIGESTS" | sed -n "s#^${recovery_rel}:##p" | wc -l | tr -d ' ')" = "1" ] || \
      fail "invalid recovery lockfile: duplicate digest for $recovery_rel"
  done
  for recovery_entry in $RECOVERY_DIGESTS; do
    recovery_digest_path="${recovery_entry%%:*}"
    recovery_digest_value="${recovery_entry#*:}"
    [ "$recovery_digest_path" != "$recovery_entry" ] || fail "invalid recovery lockfile: malformed digest entry"
    list_has "$RECOVERY_MANAGED_PATHS" "$recovery_digest_path" || \
      fail "invalid recovery lockfile: digest has no managed path: $recovery_digest_path"
    valid_sha256 "$recovery_digest_value" || fail "invalid recovery lockfile: invalid digest entry"
  done
}

recovery_expected_stage_path() {
  recovery_rel="$1"
  if [ -f "$STAGE_DIR/$recovery_rel" ] && [ ! -L "$STAGE_DIR/$recovery_rel" ]; then
    printf '%s' "$STAGE_DIR/$recovery_rel"
    return 0
  fi
  # Root agent shims are generated from this template and may be absent from a
  # minimal release fixture as individual source files.
  case "$recovery_rel" in
    AGENTS.md|CLAUDE.md|.cursor/rules/agent-rules.md|.github/copilot-instructions.md|.codex/AGENTS.md)
      [ -f "$STAGE_DIR/.beryl/agent/tool-instruction-template.md" ] || return 1
      printf '%s' "$STAGE_DIR/.beryl/agent/tool-instruction-template.md"
      ;;
    *) return 1 ;;
  esac
}

recovery_authorize_path() {
  recovery_rel="$1"
  recovery_validate_path "$recovery_rel"
  if [ "$recovery_rel" = ".beryl/lock.json" ]; then
    initial_destination_safe "$recovery_rel" || \
      fail "unsafe recovery destination (symlink, directory, or outside target): $recovery_rel"
    return 0
  fi
  list_has "$RECOVERY_AUTHORIZED_PATHS" "$recovery_rel" || \
    fail "recovery path is not authorized by staged release surface: $recovery_rel"
  initial_destination_safe "$recovery_rel" || \
    fail "unsafe recovery destination (symlink, directory, or outside target): $recovery_rel"
  recovery_expected_stage_path "$recovery_rel" >/dev/null || \
    fail "recovery path has no staged release proof: $recovery_rel"
}

recovery_build_authorized_surface() {
  RECOVERY_AUTHORIZED_PATHS=""
  for recovery_rel in $NEW_MANAGED_PATHS; do
    is_preserved_update_path "$recovery_rel" && continue
    recovery_expected_stage_path "$recovery_rel" >/dev/null || continue
    RECOVERY_AUTHORIZED_PATHS="${RECOVERY_AUTHORIZED_PATHS}
${recovery_rel}"
  done
  RECOVERY_AUTHORIZED_PATHS="$(printf '%s\n' "$RECOVERY_AUTHORIZED_PATHS" | sed '/^$/d')"
  [ -n "$RECOVERY_AUTHORIZED_PATHS" ] || fail "recovery staged release surface is empty"
}

recovery_verify_current_digests() {
  for recovery_rel in $RECOVERY_MANAGED_PATHS; do
    recovery_authorize_path "$recovery_rel"
    recovery_file="$TARGET_DIR/$recovery_rel"
    [ -f "$recovery_file" ] && [ ! -L "$recovery_file" ] || \
      fail "managed file changed or missing: $recovery_rel"
    recovery_expected="$(printf '%s\n' "$RECOVERY_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    recovery_actual="$(sha256_of "$recovery_file")"
    [ "$recovery_actual" = "$recovery_expected" ] || \
      fail "managed file changed: $recovery_rel"
    recovery_stage="$(recovery_expected_stage_path "$recovery_rel")"
    [ "$recovery_actual" = "$(sha256_of "$recovery_stage")" ] || \
      fail "managed file differs from staged release: $recovery_rel"
  done
}

recovery_add_path() {
  recovery_rel="$1"
  list_has "${RECOVERY_MUTATION_PATHS:-}" "$recovery_rel" || \
    RECOVERY_MUTATION_PATHS="${RECOVERY_MUTATION_PATHS:-}
${recovery_rel}"
}

recovery_snapshot_path() {
  recovery_rel="$1"
  recovery_validate_path "$recovery_rel"
  recovery_target="$TARGET_DIR/$recovery_rel"
  if [ -e "$recovery_target" ] || [ -L "$recovery_target" ]; then
    mkdir -p "$ROLLBACK_DIR/files/$(dirname "$recovery_rel")" || fail "could not snapshot recovery path: $recovery_rel"
    cp -p "$recovery_target" "$ROLLBACK_DIR/files/$recovery_rel" || fail "could not snapshot recovery path: $recovery_rel"
  else
    mkdir -p "$ROLLBACK_DIR/missing/$(dirname "$recovery_rel")" || fail "could not snapshot recovery path: $recovery_rel"
    : >"$ROLLBACK_DIR/missing/$recovery_rel"
  fi
}

recovery_capture_hooks() {
  RECOVERY_HOOKS_CAPTURED="false"
  RECOVERY_HOOKS_PRESENT="false"
  RECOVERY_HOOKS_PATH=""
  command -v git >/dev/null 2>&1 || return 0
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  RECOVERY_HOOKS_CAPTURED="true"
  if git -C "$TARGET_DIR" config --local --get core.hooksPath >"$ROLLBACK_DIR/recovery-hooks-path"; then
    RECOVERY_HOOKS_PRESENT="true"
    RECOVERY_HOOKS_PATH="$(cat "$ROLLBACK_DIR/recovery-hooks-path")"
  fi
}

recovery_snapshot_begin() {
  ROLLBACK_DIR="$TMP_DIR/recovery-rollback"
  mkdir -p "$ROLLBACK_DIR/files" "$ROLLBACK_DIR/missing" || fail "could not create recovery rollback directory"
  for recovery_rel in $RECOVERY_MUTATION_PATHS; do recovery_snapshot_path "$recovery_rel"; done
  recovery_capture_hooks
  RECOVERY_ROLLBACK_READY="1"
}

recovery_prune_empty_parent() {
  recovery_prune_rel="$(dirname "$1")"
  while [ "$recovery_prune_rel" != "." ] && [ "$recovery_prune_rel" != "/" ]; do
    rmdir "$TARGET_DIR/$recovery_prune_rel" 2>/dev/null || break
    recovery_prune_rel="$(dirname "$recovery_prune_rel")"
  done
}

recovery_rollback() {
  [ "${RECOVERY_ROLLBACK_READY:-0}" = "1" ] || { printf 'not-started'; return 0; }
  recovery_result="ok"
  for recovery_rel in $RECOVERY_MUTATION_PATHS; do
    recovery_target="$TARGET_DIR/$recovery_rel"
    if [ -f "$ROLLBACK_DIR/missing/$recovery_rel" ]; then
      rm -f "$recovery_target" 2>/dev/null || recovery_result="failed"
      recovery_prune_empty_parent "$recovery_rel"
    else
      rm -f "$recovery_target" 2>/dev/null || recovery_result="failed"
      mkdir -p "$(dirname "$recovery_target")" 2>/dev/null || recovery_result="failed"
      cp -p "$ROLLBACK_DIR/files/$recovery_rel" "$recovery_target" 2>/dev/null || recovery_result="failed"
    fi
  done
  if [ "$RECOVERY_HOOKS_CAPTURED" = "true" ]; then
    if [ "$RECOVERY_HOOKS_PRESENT" = "true" ]; then
      git -C "$TARGET_DIR" config --local core.hooksPath "$RECOVERY_HOOKS_PATH" 2>/dev/null || recovery_result="failed"
    else
      git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
    fi
  fi
  printf '%s' "$recovery_result"
}

recovery_abort() {
  recovery_reason="$1"
  recovery_status="not-started"
  [ "${RECOVERY_ROLLBACK_READY:-0}" = "1" ] && recovery_status="$(recovery_rollback)"
  printf 'beryl: recovery failed action=%s reason=%s rollback=%s\n' "$RECOVERY_ACTION" "$recovery_reason" "$recovery_status" >&2
  exit 1
}

recovery_validate_backup_id() {
  case "$1" in
    ""|.|..|*/*|*'..'*|*[!A-Za-z0-9._-]*) fail "invalid backup id: $1" ;;
  esac
}

recovery_validate_backup() {
  recovery_validate_backup_id "$RESTORE_BACKUP_ID"
  RECOVERY_BACKUP_DIR="$TARGET_DIR/.beryl/.updates/$RESTORE_BACKUP_ID"
  [ ! -L "$TARGET_DIR/.beryl" ] && [ ! -L "$TARGET_DIR/.beryl/.updates" ] && [ ! -L "$RECOVERY_BACKUP_DIR" ] || \
    fail "restore backup path must not contain a symlink"
  [ -d "$RECOVERY_BACKUP_DIR" ] || fail "backup not found: $RESTORE_BACKUP_ID"
  RECOVERY_METADATA="$RECOVERY_BACKUP_DIR/metadata.json"
  [ -f "$RECOVERY_METADATA" ] && [ ! -L "$RECOVERY_METADATA" ] || fail "invalid backup metadata"
  grep -q '"schemaVersion"[[:space:]]*:[[:space:]]*1' "$RECOVERY_METADATA" || fail "invalid backup metadata schema"
  [ "$(lock_string_field "$RECOVERY_METADATA" backupId)" = "$RESTORE_BACKUP_ID" ] || fail "invalid backup metadata id"
  RECOVERY_SNAPSHOT_PATHS="$(lock_array_field "$RECOVERY_METADATA" snapshotPaths)"
  RECOVERY_MISSING_PATHS="$(lock_array_field "$RECOVERY_METADATA" missingPaths)"
  RECOVERY_REPLACEMENT_MANAGED_PATHS="$(lock_array_field "$RECOVERY_METADATA" replacementManagedPaths)"
  [ -n "$RECOVERY_SNAPSHOT_PATHS" ] || fail "invalid backup metadata: snapshotPaths is empty"
  [ -n "$RECOVERY_REPLACEMENT_MANAGED_PATHS" ] || fail "invalid backup metadata: replacementManagedPaths is empty"
  recovery_seen=""
  for recovery_rel in $RECOVERY_SNAPSHOT_PATHS; do
    list_has "$recovery_seen" "$recovery_rel" && fail "invalid backup metadata: duplicate snapshot path"
    recovery_seen="${recovery_seen}
${recovery_rel}"
    recovery_validate_path "$recovery_rel"
    if list_has "$RECOVERY_MISSING_PATHS" "$recovery_rel"; then continue; fi
    recovery_source="$RECOVERY_BACKUP_DIR/files/$recovery_rel"
    [ -f "$recovery_source" ] && [ ! -L "$recovery_source" ] || fail "invalid backup snapshot: $recovery_rel"
  done
  for recovery_rel in $RECOVERY_MISSING_PATHS; do
    list_has "$RECOVERY_SNAPSHOT_PATHS" "$recovery_rel" || fail "invalid backup metadata: missing path outside snapshot"
  done
  for recovery_rel in $RECOVERY_REPLACEMENT_MANAGED_PATHS; do
    recovery_validate_path "$recovery_rel"
  done
  list_has "$RECOVERY_SNAPSHOT_PATHS" .beryl/lock.json || fail "invalid backup metadata: lock snapshot missing"
  list_has "$RECOVERY_MISSING_PATHS" .beryl/lock.json && fail "invalid backup metadata: lock cannot be missing"
  RECOVERY_RESTORED_LOCK="$RECOVERY_BACKUP_DIR/files/.beryl/lock.json"
  recovery_validate_lock "$RECOVERY_RESTORED_LOCK"
  RECOVERY_RESTORED_MANAGED_PATHS="$RECOVERY_MANAGED_PATHS"
  RECOVERY_RESTORED_DIGESTS="$RECOVERY_DIGESTS"
  RECOVERY_BACKUP_HOOKS_CAPTURED="$(lock_boolean_field "$RECOVERY_METADATA" gitHooksCaptured)"
  RECOVERY_BACKUP_HOOKS_PRESENT="$(lock_boolean_field "$RECOVERY_METADATA" gitHooksPathPresent)"
  RECOVERY_BACKUP_HOOKS_PATH="$(lock_string_field "$RECOVERY_METADATA" gitHooksPath)"
  case "$RECOVERY_BACKUP_HOOKS_CAPTURED:$RECOVERY_BACKUP_HOOKS_PRESENT" in true:true|true:false|false:false) ;; *) fail "invalid backup hook metadata" ;; esac
}

recovery_preflight_hook_state() {
  [ "$RECOVERY_CURRENT_GITHOOKS_ENABLED" = "true" ] || return 0
  command -v git >/dev/null 2>&1 || fail "recovery cannot verify active Beryl hooks without Git"
  git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    fail "recovery cannot verify active Beryl hooks outside a Git worktree"
  recovery_current_hooks="$(git -C "$TARGET_DIR" config --local --get core.hooksPath || true)"
  [ "$recovery_current_hooks" = ".beryl/githooks" ] || \
    fail "recovery refuses to change files after core.hooksPath was changed by the user"
}

recovery_authorize_backup() {
  for recovery_rel in $RECOVERY_SNAPSHOT_PATHS; do
    recovery_authorize_path "$recovery_rel"
    [ "$recovery_rel" = ".beryl/lock.json" ] && continue
    list_has "$RECOVERY_RESTORED_MANAGED_PATHS" "$recovery_rel" || \
      fail "backup snapshot path is not owned by restored lock: $recovery_rel"
    recovery_expected="$(printf '%s\n' "$RECOVERY_RESTORED_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    [ -n "$recovery_expected" ] || fail "backup snapshot path has no restored digest: $recovery_rel"
    recovery_snapshot_file="$RECOVERY_BACKUP_DIR/files/$recovery_rel"
    [ -f "$recovery_snapshot_file" ] && [ ! -L "$recovery_snapshot_file" ] || \
      fail "backup snapshot is not a regular file: $recovery_rel"
    recovery_stage="$(recovery_expected_stage_path "$recovery_rel")"
    [ "$(sha256_of "$recovery_snapshot_file")" = "$recovery_expected" ] || \
      fail "backup snapshot digest differs from restored lock: $recovery_rel"
    [ "$recovery_expected" = "$(sha256_of "$recovery_stage")" ] || \
      fail "backup lock digest differs from staged release: $recovery_rel"
  done
  for recovery_rel in $RECOVERY_RESTORED_MANAGED_PATHS; do
    recovery_authorize_path "$recovery_rel"
    list_has "$RECOVERY_SNAPSHOT_PATHS" "$recovery_rel" || \
      fail "restored managed path is missing from backup snapshot: $recovery_rel"
    list_has "$RECOVERY_MISSING_PATHS" "$recovery_rel" && \
      fail "restored managed path cannot be marked missing: $recovery_rel"
    recovery_expected="$(printf '%s\n' "$RECOVERY_RESTORED_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    recovery_stage="$(recovery_expected_stage_path "$recovery_rel")"
    [ "$recovery_expected" = "$(sha256_of "$recovery_stage")" ] || \
      fail "backup lock digest differs from staged release: $recovery_rel"
  done
}

recovery_current_source_path_is_selected() {
  recovery_rel="$1"
  for recovery_component in $RECOVERY_CURRENT_AUTH_COMPONENTS; do
    for recovery_base in $(component_field "$recovery_component" paths) $(component_field "$recovery_component" rootPaths); do
      case "$recovery_base" in
        */) case "$recovery_rel" in "$recovery_base"*) return 0 ;; esac ;;
        *) [ "$recovery_rel" = "$recovery_base" ] && return 0 ;;
      esac
    done
  done
  return 1
}

recovery_stage_current_surface() {
  # Restore's --source-dir proves the historical release. A second explicit
  # checkout proves the currently installed release before Beryl removes files
  # which the historical lock does not own. Reusing the historical checkout is
  # safe only when it actually contains byte-identical current files.
  RECOVERY_CURRENT_STAGE_DIR="$TMP_DIR/recovery-current-stage"
  mkdir -p "$RECOVERY_CURRENT_STAGE_DIR" || fail "could not create current recovery stage"
  recovery_saved_manifest="$MANIFEST"
  recovery_current_source="${RECOVERY_CURRENT_SOURCE_DIR:-$SOURCE_DIR}"
  if [ -n "$recovery_current_source" ]; then
    recovery_current_source="$(cd "$recovery_current_source" && pwd)" || fail "could not resolve current recovery source"
    [ -f "$recovery_current_source/.beryl/beryl.components.json" ] || fail "missing current recovery source manifest"
    git -C "$recovery_current_source" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
      fail "current recovery source must be a Git checkout"
    MANIFEST="$recovery_current_source/.beryl/beryl.components.json"
    recovery_current_source_kind="git"
  else
    [ "$ARCHIVE_URL_EXPLICIT" = "0" ] || fail "restore with a custom archive needs --current-source-dir"
    recovery_current_archive="$TMP_DIR/recovery-current.tar.gz"
    recovery_current_url="https://codeload.github.com/$REPO_SLUG/tar.gz/$RECOVERY_CURRENT_SOURCE_REF"
    fetch_https "$recovery_current_url" "$recovery_current_archive" || fail "could not fetch current recovery archive"
    recovery_current_actual_sha="$(sha256_of "$recovery_current_archive")"
    [ "$recovery_current_actual_sha" = "$RECOVERY_CURRENT_EXPECTED_SOURCE_SHA256" ] || \
      fail "current recovery archive SHA-256 mismatch"
    tar -tzf "$recovery_current_archive" >"$TMP_DIR/recovery-current-list" || fail "could not inspect current recovery archive"
    recovery_current_prefix="$(sed -n '1s#/$##p; q' "$TMP_DIR/recovery-current-list")"
    [ -n "$recovery_current_prefix" ] || fail "could not detect current recovery archive prefix"
    tar -xzf "$recovery_current_archive" -C "$TMP_DIR" --strip-components=1 \
      "$recovery_current_prefix/.beryl/beryl.components.json" || fail "current recovery archive lacks manifest"
    MANIFEST="$TMP_DIR/.beryl/beryl.components.json"
    recovery_current_source_kind="archive"
  fi
  [ "$RECOVERY_CURRENT_SELECTION_EXPLICIT" = "1" ] || \
    fail "restore removal requires explicit --current-profile or --current-components authorization"
  if [ -n "$RECOVERY_CURRENT_COMPONENTS_CSV" ]; then
    RECOVERY_CURRENT_AUTH_COMPONENTS="$(split_csv "$RECOVERY_CURRENT_COMPONENTS_CSV")"
  else
    RECOVERY_CURRENT_AUTH_COMPONENTS="$(profile_components "$RECOVERY_CURRENT_PROFILE")"
  fi
  recovery_current_changed=1
  while [ "$recovery_current_changed" = "1" ]; do
    recovery_current_changed=0
    for recovery_component in $RECOVERY_CURRENT_AUTH_COMPONENTS; do
      [ -n "$(manifest_line component "$recovery_component")" ] || \
        fail "current recovery source does not define authorized component: $recovery_component"
      for recovery_dep in $(component_field "$recovery_component" requires); do
        if ! list_has "$RECOVERY_CURRENT_AUTH_COMPONENTS" "$recovery_dep"; then
          RECOVERY_CURRENT_AUTH_COMPONENTS="${RECOVERY_CURRENT_AUTH_COMPONENTS}
${recovery_dep}"
          recovery_current_changed=1
        fi
      done
    done
  done
  validate_lock_selection "invalid current recovery lockfile" "$RECOVERY_CURRENT_REQUESTED_COMPONENTS" "$RECOVERY_CURRENT_LOCK_COMPONENTS"
  lock_component_sets_equal "$RECOVERY_CURRENT_LOCK_COMPONENTS" "$RECOVERY_CURRENT_AUTH_COMPONENTS" || \
    fail "invalid current recovery lockfile: resolved components do not match explicit current restore selection"
  validate_lock_managed_surface "invalid current recovery lockfile" "$RECOVERY_CURRENT_MANAGED_PATHS" "$RECOVERY_CURRENT_LOCK_COMPONENTS"
  for recovery_rel in $RECOVERY_CURRENT_MANAGED_PATHS; do
    recovery_validate_path "$recovery_rel"
    recovery_current_source_path_is_selected "$recovery_rel" || \
      fail "current recovery lock path is not selected by source manifest: $recovery_rel"
    mkdir -p "$RECOVERY_CURRENT_STAGE_DIR/$(dirname "$recovery_rel")" || fail "could not stage current recovery file"
    if [ "$recovery_current_source_kind" = "git" ]; then
      recovery_source_file="$recovery_current_source/$recovery_rel"
      [ -f "$recovery_source_file" ] && [ ! -L "$recovery_source_file" ] || \
        fail "current recovery source lacks regular file: $recovery_rel"
      git -C "$recovery_current_source" ls-files --error-unmatch -- "$recovery_rel" >/dev/null 2>&1 || \
        fail "current recovery source file is not tracked: $recovery_rel"
      cp -p "$recovery_source_file" "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel" || fail "could not stage current recovery file"
    else
      tar -xzf "$recovery_current_archive" -C "$RECOVERY_CURRENT_STAGE_DIR" --strip-components=1 \
        "$recovery_current_prefix/$recovery_rel" || fail "current recovery archive lacks path: $recovery_rel"
      [ -f "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel" ] && [ ! -L "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel" ] || \
        fail "current recovery archive path is not a regular file: $recovery_rel"
    fi
  done
  MANIFEST="$recovery_saved_manifest"
}

recovery_authorize_current_path() {
  recovery_rel="$1"
  recovery_validate_path "$recovery_rel"
  initial_destination_safe "$recovery_rel" || \
    fail "unsafe recovery destination (symlink, directory, or outside target): $recovery_rel"
  [ -f "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel" ] && [ ! -L "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel" ] || \
    fail "current recovery path lacks staged release proof: $recovery_rel"
}

recovery_verify_restore_current_state() {
  # Restoring an old snapshot must not overwrite a user-modified file merely
  # because the backup names it. The current lock provides state only; its
  # digest is used as a change detector, while the restored content is proved
  # separately against the staged old release in recovery_authorize_backup.
  for recovery_rel in $RECOVERY_SNAPSHOT_PATHS; do
    list_has "$RECOVERY_CURRENT_MANAGED_PATHS" "$recovery_rel" || continue
    recovery_validate_path "$recovery_rel"
    initial_destination_safe "$recovery_rel" || \
      fail "unsafe recovery destination (symlink, directory, or outside target): $recovery_rel"
    recovery_authorize_current_path "$recovery_rel"
    recovery_current_expected="$(printf '%s\n' "$RECOVERY_CURRENT_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    [ -n "$recovery_current_expected" ] || fail "current recovery lock missing digest: $recovery_rel"
    [ -f "$TARGET_DIR/$recovery_rel" ] && [ ! -L "$TARGET_DIR/$recovery_rel" ] || \
      fail "current managed file changed or missing: $recovery_rel"
    [ "$(sha256_of "$TARGET_DIR/$recovery_rel")" = "$recovery_current_expected" ] || \
      fail "current managed file changed: $recovery_rel"
    [ "$recovery_current_expected" = "$(sha256_of "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel")" ] || \
      fail "current lock digest differs from staged current release: $recovery_rel"
  done
}

recovery_replace_lock_from() {
  recovery_lock_source="$1"
  recovery_lock_tmp="$(create_target_lock_tmp)" || \
    recovery_abort "could not create secure restore lock candidate"
  case "${BERYL_RECOVERY_TEST_REQUIRE_TARGET_SIBLING:-0}" in
    0) ;;
    1) case "$recovery_lock_tmp" in "$TARGET_DIR/.beryl/"*) ;; *) recovery_abort "restore lock staging is not target-sibling" ;; esac ;;
    *) recovery_abort "invalid recovery staging test seam" ;;
  esac
  cp -p "$recovery_lock_source" "$recovery_lock_tmp" || recovery_abort "stage restored lock"
  mv "$recovery_lock_tmp" "$TARGET_DIR/.beryl/lock.json" || {
    rm -f "$recovery_lock_tmp" 2>/dev/null || true
    recovery_abort "write restored lock"
  }
}

run_restore_action() {
  recovery_preflight_hook_state
  recovery_stage_current_surface
  recovery_authorize_backup
  recovery_verify_restore_current_state
  RECOVERY_REMOVED_ON_RESTORE=""
  for recovery_rel in $RECOVERY_CURRENT_MANAGED_PATHS; do
    list_has "$RECOVERY_RESTORED_MANAGED_PATHS" "$recovery_rel" && continue
    # Metadata records the update result, but only the fresh current-release
    # stage and current lock digest authorize deleting this now-absent old path.
    list_has "$RECOVERY_REPLACEMENT_MANAGED_PATHS" "$recovery_rel" || \
      fail "current managed path is absent from backup replacement state: $recovery_rel"
    recovery_authorize_current_path "$recovery_rel"
    recovery_current_expected="$(printf '%s\n' "$RECOVERY_CURRENT_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    [ -n "$recovery_current_expected" ] || fail "current recovery lock missing digest: $recovery_rel"
    [ -f "$TARGET_DIR/$recovery_rel" ] && [ ! -L "$TARGET_DIR/$recovery_rel" ] || \
      fail "current managed file changed or missing: $recovery_rel"
    [ "$(sha256_of "$TARGET_DIR/$recovery_rel")" = "$recovery_current_expected" ] || \
      fail "current managed file changed: $recovery_rel"
    [ "$recovery_current_expected" = "$(sha256_of "$RECOVERY_CURRENT_STAGE_DIR/$recovery_rel")" ] || \
      fail "current lock digest differs from staged current release: $recovery_rel"
    RECOVERY_REMOVED_ON_RESTORE="${RECOVERY_REMOVED_ON_RESTORE}
${recovery_rel}"
  done
  for recovery_rel in $RECOVERY_REPLACEMENT_MANAGED_PATHS; do
    list_has "$RECOVERY_CURRENT_MANAGED_PATHS" "$recovery_rel" || \
      fail "backup replacement path is not owned by current lock: $recovery_rel"
  done
  RECOVERY_REMOVED_ON_RESTORE="$(printf '%s\n' "$RECOVERY_REMOVED_ON_RESTORE" | sed '/^$/d')"
  RECOVERY_MUTATION_PATHS=""
  for recovery_rel in $RECOVERY_SNAPSHOT_PATHS; do recovery_add_path "$recovery_rel"; done
  for recovery_rel in $RECOVERY_REMOVED_ON_RESTORE; do recovery_add_path "$recovery_rel"; done
  recovery_snapshot_begin
  for recovery_rel in $RECOVERY_SNAPSHOT_PATHS; do
    [ "$recovery_rel" = ".beryl/lock.json" ] && continue
    recovery_target="$TARGET_DIR/$recovery_rel"
    if list_has "$RECOVERY_MISSING_PATHS" "$recovery_rel"; then
      rm -f "$recovery_target" || recovery_abort "remove $recovery_rel"
      recovery_prune_empty_parent "$recovery_rel"
    else
      mkdir -p "$(dirname "$recovery_target")" || recovery_abort "mkdir $recovery_rel"
      cp -p "$RECOVERY_BACKUP_DIR/files/$recovery_rel" "$recovery_target" || recovery_abort "copy $recovery_rel"
    fi
  done
  for recovery_rel in $RECOVERY_RESTORED_MANAGED_PATHS; do
    recovery_target="$TARGET_DIR/$recovery_rel"
    recovery_expected="$(printf '%s\n' "$RECOVERY_RESTORED_DIGESTS" | sed -n "s#^${recovery_rel}:##p")"
    recovery_stage="$(recovery_expected_stage_path "$recovery_rel")"
    [ -f "$recovery_target" ] && [ ! -L "$recovery_target" ] && \
      [ "$(sha256_of "$recovery_target")" = "$recovery_expected" ] && \
      [ "$recovery_expected" = "$(sha256_of "$recovery_stage")" ] || recovery_abort "restored digest mismatch: $recovery_rel"
  done
  for recovery_rel in $RECOVERY_REMOVED_ON_RESTORE; do
    rm -f "$TARGET_DIR/$recovery_rel" || recovery_abort "remove newer managed path $recovery_rel"
    recovery_prune_empty_parent "$recovery_rel"
  done
  # A preserve-mode installation never owned Git's hook configuration. Even
  # if backup metadata records what update observed, it cannot authorize a
  # later restore to replace that target-owned setting.
  if [ "$RECOVERY_CURRENT_GITHOOKS_ENABLED" = "true" ] && [ "$RECOVERY_BACKUP_HOOKS_CAPTURED" = "true" ]; then
    if [ "$RECOVERY_BACKUP_HOOKS_PRESENT" = "true" ]; then
      git -C "$TARGET_DIR" config --local core.hooksPath "$RECOVERY_BACKUP_HOOKS_PATH" || recovery_abort "restore Git hooks path"
    else
      git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
    fi
  fi
  recovery_replace_lock_from "$RECOVERY_RESTORED_LOCK"
  printf 'beryl: restore complete backup=%s\n' "$RESTORE_BACKUP_ID"
}

run_uninstall_action() {
  recovery_preflight_hook_state
  recovery_verify_current_digests
  RECOVERY_MUTATION_PATHS=""
  for recovery_rel in $RECOVERY_MANAGED_PATHS; do recovery_add_path "$recovery_rel"; done
  recovery_add_path .beryl/lock.json
  recovery_snapshot_begin
  for recovery_rel in $RECOVERY_MANAGED_PATHS; do
    rm -f "$TARGET_DIR/$recovery_rel" || recovery_abort "remove $recovery_rel"
    recovery_prune_empty_parent "$recovery_rel"
  done
  if [ "$RECOVERY_CURRENT_GITHOOKS_ENABLED" = "true" ] && [ "$RECOVERY_CURRENT_PREVIOUS_HOOKS_PATH_PRESENT" = "true" ]; then
    git -C "$TARGET_DIR" config --local core.hooksPath "$RECOVERY_CURRENT_PREVIOUS_HOOKS_PATH" || recovery_abort "restore previous Git hooks path"
  elif [ "$RECOVERY_CURRENT_GITHOOKS_ENABLED" = "true" ]; then
    git -C "$TARGET_DIR" config --local --unset-all core.hooksPath >/dev/null 2>&1 || true
  fi
  rm -f "$TARGET_DIR/.beryl/lock.json" || recovery_abort "remove lockfile"
  recovery_prune_empty_parent .beryl/lock.json
  printf 'beryl: uninstall complete\n'
}

run_adopt_action() {
  [ ! -e "$TARGET_DIR/.beryl/lock.json" ] && [ ! -L "$TARGET_DIR/.beryl/lock.json" ] || \
    fail "adoption refuses an existing lockfile"
  [ -d "$TARGET_DIR/.beryl" ] && [ ! -L "$TARGET_DIR/.beryl" ] || \
    fail "adoption requires an existing non-symlink .beryl directory"
  find "$TARGET_DIR/.beryl" -type l -print -quit | grep -q . && fail "adoption refuses symlinks in existing .beryl"
  if command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [ "$(git -C "$TARGET_DIR" config --local --get core.hooksPath || true)" != ".beryl/githooks" ] || \
      fail "adoption refuses active Beryl hooks without proven prior hook state"
  fi
  FINAL_MANAGED_PATHS=""
  ADOPTION_PRESERVED=""
  ADOPTION_CONFLICTS=""
  for recovery_rel in $NEW_MANAGED_PATHS; do
    if is_preserved_update_path "$recovery_rel"; then
      ADOPTION_PRESERVED="${ADOPTION_PRESERVED}
${recovery_rel}"; continue; fi
    recovery_validate_path "$recovery_rel"
    if [ -f "$TARGET_DIR/$recovery_rel" ] && [ ! -L "$TARGET_DIR/$recovery_rel" ] && \
       cmp -s "$(recovery_expected_stage_path "$recovery_rel")" "$TARGET_DIR/$recovery_rel"; then
      FINAL_MANAGED_PATHS="${FINAL_MANAGED_PATHS}
${recovery_rel}"
    else
      ADOPTION_CONFLICTS="${ADOPTION_CONFLICTS}
${recovery_rel}"
    fi
  done
  FINAL_MANAGED_PATHS="$(printf '%s\n' "$FINAL_MANAGED_PATHS" | sed '/^$/d')"
  ADOPTION_PRESERVED="$(printf '%s\n' "$ADOPTION_PRESERVED" | sed '/^$/d')"
  ADOPTION_CONFLICTS="$(printf '%s\n' "$ADOPTION_CONFLICTS" | sed '/^$/d')"
  printf 'beryl: adoption candidate managed paths:\n'; printf '%s\n' "$FINAL_MANAGED_PATHS" | sed '/^$/d; s/^/  /'
  printf 'beryl: adoption preserved target paths:\n'; printf '%s\n' "$ADOPTION_PRESERVED" | sed '/^$/d; s/^/  /'
  [ -z "$ADOPTION_CONFLICTS" ] || { printf 'beryl: adoption conflicts:\n' >&2; printf '%s\n' "$ADOPTION_CONFLICTS" | sed '/^$/d; s/^/  /' >&2; fail "adoption requires identical staged files"; }
  [ -n "$FINAL_MANAGED_PATHS" ] || fail "adoption found no identical Beryl-managed files"
  [ "$DRY_RUN" = "0" ] || { printf 'beryl: adoption dry-run complete; no files changed\n'; exit 0; }
  ROOT_CONFLICT="skip"
  ROOT_CONFLICT_DECISIONS=""
  for recovery_rel in $ADOPTION_PRESERVED; do
    case "$recovery_rel" in
      .beryl/*) ;;
      *) ROOT_CONFLICT_DECISIONS="${ROOT_CONFLICT_DECISIONS}
skip:${recovery_rel}" ;;
    esac
  done
  ROOT_CONFLICT_DECISIONS="$(printf '%s\n' "$ROOT_CONFLICT_DECISIONS" | sed '/^$/d')"
  GIT_HOOKS_ENABLED="false"
  GIT_HOOKS_PREVIOUS_PATH_PRESENT="false"
  GIT_HOOKS_PREVIOUS_PATH=""
  write_lockfile
  printf 'beryl: adoption complete\n'
}

PROFILE="standard"
COMPONENTS_CSV=""
INTERACTIVE="0"
INTERACTIVE_EXPLICIT="0"
EXPLICIT_COMPONENT_SELECTION="0"
UPDATE_MODE="0"
UPDATE_EXPLICIT="0"
RESTORE_BACKUP_ID=""
RECOVERY_CURRENT_SOURCE_DIR=""
RECOVERY_CURRENT_SOURCE_DIR_EXPLICIT="0"
RECOVERY_CURRENT_PROFILE=""
RECOVERY_CURRENT_COMPONENTS_CSV=""
RECOVERY_CURRENT_SELECTION_EXPLICIT="0"
UNINSTALL_MODE="0"
ADOPT_MODE="0"
RECOVERY_ACTION=""
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
INITIAL_TRANSACTION_READY="0"
INITIAL_TARGET_EXISTED="1"
BACKUP_CREATED="0"
UPDATE_BACKUP_PARENT_CREATED="0"
LIFECYCLE_LOCK_HELD="0"
LIFECYCLE_LOCK_DIR=""
LIFECYCLE_CREATED_TARGET="0"
LIFECYCLE_TARGET_MTIME_FILE=""
LIFECYCLE_COMMITTED="0"
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
SOURCE_DIR_EXPLICIT="0"
REMOTE_SOURCE_EXPLICIT="0"
SOURCE_REF="$DEFAULT_REF"
SOURCE_REF_EXPLICIT="0"
ARCHIVE_URL="$DEFAULT_ARCHIVE_URL"
ARCHIVE_URL_EXPLICIT="0"
ROOT_CONFLICT="fail"
ROOT_CONFLICT_EXPLICIT="0"
ROOT_CONFLICT_DECISIONS=""
LOCK_ROOT_CONFLICT="fail"
LOCK_ROOT_CONFLICT_DECISIONS=""
LOCK_PRESERVED_ROOT_DIGESTS=""
ENABLE_GITHOOKS="0"
ENABLE_GITHOOKS_EXPLICIT="0"
HOOK_CONFLICT="fail"
HOOK_CONFLICT_EXPLICIT="0"
LOCK_HOOK_CONFLICT="fail"
LOCK_GITHOOKS_ENABLED="false"
LOCK_PREVIOUS_HOOKS_PATH_PRESENT="false"
LOCK_PREVIOUS_HOOKS_PATH=""
GIT_HOOKS_CONFIGURE="0"
GIT_HOOKS_ENABLED="false"
GIT_HOOKS_PREVIOUS_PATH_PRESENT="false"
GIT_HOOKS_PREVIOUS_PATH=""
PREFLIGHT_HOOKS_PATH_PRESENT="false"
PREFLIGHT_HOOKS_PATH=""
GITHOOKS_REMOVED="0"
GIT_HOOKS_RESTORE="0"
EXPECTED_SHA256=""
EXPECTED_SHA256_EXPLICIT="0"
DRY_RUN="0"
TMP_DIR=""
MANIFEST=""
trap 'release_lifecycle_lock; [ -z "${TMP_DIR:-}" ] || rm -rf "$TMP_DIR"' EXIT INT TERM

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --interactive)
      INTERACTIVE="1"
      INTERACTIVE_EXPLICIT="1"
      shift
      ;;
    --update)
      UPDATE_MODE="1"
      UPDATE_EXPLICIT="1"
      shift
      ;;
    --restore)
      [ "$#" -ge 2 ] || fail "--restore requires a backup id"
      RESTORE_BACKUP_ID="$2"
      shift 2
      ;;
    --restore=*)
      RESTORE_BACKUP_ID="${1#--restore=}"
      shift
      ;;
    --current-source-dir)
      [ "$#" -ge 2 ] || fail "--current-source-dir requires a value"
      RECOVERY_CURRENT_SOURCE_DIR="$2"
      RECOVERY_CURRENT_SOURCE_DIR_EXPLICIT="1"
      shift 2
      ;;
    --current-source-dir=*)
      RECOVERY_CURRENT_SOURCE_DIR="${1#--current-source-dir=}"
      RECOVERY_CURRENT_SOURCE_DIR_EXPLICIT="1"
      shift
      ;;
    --current-profile)
      [ "$#" -ge 2 ] || fail "--current-profile requires a value"
      RECOVERY_CURRENT_PROFILE="$2"
      RECOVERY_CURRENT_COMPONENTS_CSV=""
      RECOVERY_CURRENT_SELECTION_EXPLICIT="1"
      shift 2
      ;;
    --current-profile=*)
      RECOVERY_CURRENT_PROFILE="${1#--current-profile=}"
      RECOVERY_CURRENT_COMPONENTS_CSV=""
      RECOVERY_CURRENT_SELECTION_EXPLICIT="1"
      shift
      ;;
    --current-components)
      [ "$#" -ge 2 ] || fail "--current-components requires a value"
      RECOVERY_CURRENT_COMPONENTS_CSV="$2"
      RECOVERY_CURRENT_PROFILE=""
      RECOVERY_CURRENT_SELECTION_EXPLICIT="1"
      shift 2
      ;;
    --current-components=*)
      RECOVERY_CURRENT_COMPONENTS_CSV="${1#--current-components=}"
      RECOVERY_CURRENT_PROFILE=""
      RECOVERY_CURRENT_SELECTION_EXPLICIT="1"
      shift
      ;;
    --uninstall)
      UNINSTALL_MODE="1"
      shift
      ;;
    --adopt-existing)
      ADOPT_MODE="1"
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
      SOURCE_DIR_EXPLICIT="1"
      shift 2
      ;;
    --source-dir=*)
      SOURCE_DIR="${1#--source-dir=}"
      SOURCE_DIR_EXPLICIT="1"
      shift
      ;;
    --ref)
      [ "$#" -ge 2 ] || fail "--ref requires a value"
      SOURCE_REF="$2"
      set_default_remote_urls_for_ref
      SOURCE_REF_EXPLICIT="1"
      REMOTE_SOURCE_EXPLICIT="1"
      shift 2
      ;;
    --ref=*)
      SOURCE_REF="${1#--ref=}"
      set_default_remote_urls_for_ref
      SOURCE_REF_EXPLICIT="1"
      REMOTE_SOURCE_EXPLICIT="1"
      shift
      ;;
    --archive-url)
      [ "$#" -ge 2 ] || fail "--archive-url requires a value"
      ARCHIVE_URL="$2"
      ARCHIVE_URL_EXPLICIT="1"
      REMOTE_SOURCE_EXPLICIT="1"
      shift 2
      ;;
    --archive-url=*)
      ARCHIVE_URL="${1#--archive-url=}"
      ARCHIVE_URL_EXPLICIT="1"
      REMOTE_SOURCE_EXPLICIT="1"
      shift
      ;;
    --root-conflict)
      [ "$#" -ge 2 ] || fail "--root-conflict requires a value"
      ROOT_CONFLICT="$2"
      ROOT_CONFLICT_EXPLICIT="1"
      shift 2
      ;;
    --root-conflict=*)
      ROOT_CONFLICT="${1#--root-conflict=}"
      ROOT_CONFLICT_EXPLICIT="1"
      shift
      ;;
    --enable-githooks)
      ENABLE_GITHOOKS="1"
      ENABLE_GITHOOKS_EXPLICIT="1"
      shift
      ;;
    --hook-conflict)
      [ "$#" -ge 2 ] || fail "--hook-conflict requires a value"
      HOOK_CONFLICT="$2"
      HOOK_CONFLICT_EXPLICIT="1"
      shift 2
      ;;
    --hook-conflict=*)
      HOOK_CONFLICT="${1#--hook-conflict=}"
      HOOK_CONFLICT_EXPLICIT="1"
      shift
      ;;
    --expected-sha256)
      [ "$#" -ge 2 ] || fail "--expected-sha256 requires a value"
      EXPECTED_SHA256="$2"
      EXPECTED_SHA256_EXPLICIT="1"
      shift 2
      ;;
    --expected-sha256=*)
      EXPECTED_SHA256="${1#--expected-sha256=}"
      EXPECTED_SHA256_EXPLICIT="1"
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

recovery_action_count=0
[ -n "$RESTORE_BACKUP_ID" ] && recovery_action_count=$((recovery_action_count + 1))
[ "$UNINSTALL_MODE" = "1" ] && recovery_action_count=$((recovery_action_count + 1))
[ "$ADOPT_MODE" = "1" ] && recovery_action_count=$((recovery_action_count + 1))
[ "$recovery_action_count" -le 1 ] || fail "--restore, --uninstall, and --adopt-existing are mutually exclusive"
[ "$recovery_action_count" = "0" ] || [ "$UPDATE_MODE" = "0" ] || fail "recovery actions cannot be combined with --update"
[ "$RECOVERY_CURRENT_SOURCE_DIR_EXPLICIT" = "0" ] || [ -n "$RESTORE_BACKUP_ID" ] || \
  fail "--current-source-dir is valid only with --restore"
[ "$RECOVERY_CURRENT_SELECTION_EXPLICIT" = "0" ] || [ -n "$RESTORE_BACKUP_ID" ] || \
  fail "--current-profile and --current-components are valid only with --restore"
if [ -n "$RESTORE_BACKUP_ID" ]; then RECOVERY_ACTION="restore"; fi
if [ "$UNINSTALL_MODE" = "1" ]; then RECOVERY_ACTION="uninstall"; fi
if [ "$ADOPT_MODE" = "1" ]; then RECOVERY_ACTION="adopt"; fi

case "$ROOT_CONFLICT" in
  fail|overwrite|skip) ;;
  *) fail "--root-conflict must be fail, overwrite, or skip" ;;
esac
case "$HOOK_CONFLICT" in
  fail|preserve|replace) ;;
  *) fail "--hook-conflict must be fail, preserve, or replace" ;;
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
validate_source_ref

if [ -n "$EXPECTED_SHA256" ]; then
  case "$EXPECTED_SHA256" in
    *[!0-9a-fA-F]*) fail "--expected-sha256 must be a 64-char hex digest" ;;
  esac
  [ "${#EXPECTED_SHA256}" -eq 64 ] || fail "--expected-sha256 must be a 64-char hex digest"
fi

if [ -z "$SOURCE_DIR" ] && [ "$UPDATE_MODE" = "0" ] && [ -z "$RECOVERY_ACTION" ] && [ "$BOOTSTRAP_AGENT" = "0" ]; then
  enforce_remote_archive_trust
fi

if [ "$BOOTSTRAP_AGENT" = "1" ]; then
  if [ "$UPDATE_EXPLICIT" = "1" ] || [ "$INTERACTIVE_EXPLICIT" = "1" ] || \
     [ "$EXPLICIT_COMPONENT_SELECTION" = "1" ] || [ "$SOURCE_DIR_EXPLICIT" = "1" ] || \
     [ "$REMOTE_SOURCE_EXPLICIT" = "1" ] || [ "$ROOT_CONFLICT_EXPLICIT" = "1" ] || \
     [ "$ENABLE_GITHOOKS_EXPLICIT" = "1" ] || [ "$HOOK_CONFLICT_EXPLICIT" = "1" ] || \
     [ "$EXPECTED_SHA256_EXPLICIT" = "1" ] || [ "$recovery_action_count" != "0" ] || \
     [ "$DRY_RUN" = "1" ]; then
    fail "--bootstrap-agent is a standalone action; use only --target and agent runner options"
  fi
  resolve_target_dir "$TARGET_DIR"
  preflight_required_runtimes
  init_tmp_dir
  run_bootstrap_action
fi

resolve_target_dir "$TARGET_DIR"

# A lifecycle must hold its per-target exclusion before it reads a mutable
# lock, backup, hook configuration, or destination state.  Dry-runs remain
# read-only and therefore do not create a target merely to lock it.
preflight_required_runtimes
init_tmp_dir
if [ "$DRY_RUN" = "0" ]; then
  acquire_lifecycle_lock
fi

if [ "$RECOVERY_ACTION" = "restore" ] || [ "$RECOVERY_ACTION" = "uninstall" ]; then
  if [ "$INTERACTIVE_EXPLICIT" = "1" ] || \
     [ "$ROOT_CONFLICT_EXPLICIT" = "1" ] || [ "$ENABLE_GITHOOKS_EXPLICIT" = "1" ] || \
     [ "$HOOK_CONFLICT_EXPLICIT" = "1" ] || \
     [ "$DRY_RUN" = "1" ]; then
    fail "--${RECOVERY_ACTION} accepts only --target and release-source options"
  fi
  if [ "$RECOVERY_ACTION" = "uninstall" ] && [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ]; then
    fail "--uninstall requires an explicit --profile or --components authorization"
  fi
  if [ "$RECOVERY_ACTION" = "restore" ] && [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ]; then
    fail "--restore requires an explicit historical --profile or --components authorization"
  fi
  preflight_required_runtimes
  recovery_validate_lock "$TARGET_DIR/.beryl/lock.json"
  RECOVERY_CURRENT_MANAGED_PATHS="$RECOVERY_MANAGED_PATHS"
  RECOVERY_CURRENT_DIGESTS="$RECOVERY_DIGESTS"
  RECOVERY_CURRENT_REQUESTED_COMPONENTS="$RECOVERY_REQUESTED_COMPONENTS"
  RECOVERY_CURRENT_LOCK_COMPONENTS="$RECOVERY_LOCK_COMPONENTS"
  RECOVERY_CURRENT_SOURCE_REF="$RECOVERY_LOCK_SOURCE_REF"
  RECOVERY_CURRENT_EXPECTED_SOURCE_SHA256="$RECOVERY_LOCK_EXPECTED_SOURCE_SHA256"
  RECOVERY_CURRENT_GITHOOKS_ENABLED="$LOCK_GITHOOKS_ENABLED"
  RECOVERY_CURRENT_PREVIOUS_HOOKS_PATH_PRESENT="$LOCK_PREVIOUS_HOOKS_PATH_PRESENT"
  RECOVERY_CURRENT_PREVIOUS_HOOKS_PATH="$LOCK_PREVIOUS_HOOKS_PATH"
  if [ "$RECOVERY_ACTION" = "restore" ]; then
    recovery_validate_backup
    RECOVERY_SELECTION_COMPONENTS=""
    RECOVERY_SELECTION_SOURCE_REF="$RECOVERY_LOCK_SOURCE_REF"
  else
    RECOVERY_SELECTION_COMPONENTS="$RECOVERY_CURRENT_REQUESTED_COMPONENTS"
    RECOVERY_SELECTION_SOURCE_REF="$RECOVERY_CURRENT_SOURCE_REF"
  fi
  if [ "$SOURCE_REF_EXPLICIT" = "0" ]; then
    SOURCE_REF="$RECOVERY_SELECTION_SOURCE_REF"
    if [ "$ARCHIVE_URL_EXPLICIT" = "0" ]; then
      set_default_remote_urls_for_ref
    fi
  elif [ -z "$SOURCE_DIR" ] && [ "$SOURCE_REF" != "$RECOVERY_SELECTION_SOURCE_REF" ]; then
    fail "recovery remote --ref must match the locked release ref"
  fi
  if [ -z "$SOURCE_DIR" ]; then
    if [ "$EXPECTED_SHA256_EXPLICIT" = "0" ]; then
      EXPECTED_SHA256="$RECOVERY_LOCK_EXPECTED_SOURCE_SHA256"
    fi
    enforce_remote_archive_trust
    if [ "$RECOVERY_ACTION" = "restore" ]; then
      is_full_commit_sha "$RECOVERY_CURRENT_SOURCE_REF" || fail "remote restore current lock requires a full 40-character commit SHA"
      valid_sha256 "$RECOVERY_CURRENT_EXPECTED_SOURCE_SHA256" || fail "remote restore current lock requires expectedSourceSha256"
    fi
  fi
fi

if [ "$UPDATE_MODE" = "1" ]; then
  UPDATE_PHASE="validate"
  UPDATE_PATH=".beryl/lock.json"
  if [ "$BOOTSTRAP_AGENT" = "1" ]; then
    set_update_context validate agent-bootstrap --bootstrap-agent
    fail "--update cannot run agent bootstrap transactionally; run bootstrap separately after a successful update"
  fi
  validate_existing_lock
  if [ "$SOURCE_REF_EXPLICIT" = "0" ]; then
    SOURCE_REF="$LOCK_SOURCE_REF"
    validate_source_ref
    if [ "$ARCHIVE_URL_EXPLICIT" = "0" ]; then
      set_default_remote_urls_for_ref
    fi
  fi
  if [ -z "$SOURCE_DIR" ]; then
    if [ "$SOURCE_REF_EXPLICIT" = "1" ] && [ "$EXPECTED_SHA256_EXPLICIT" = "0" ]; then
      fail "remote update with an explicit --ref also requires an explicit --expected-sha256"
    fi
    if [ "$EXPECTED_SHA256_EXPLICIT" = "0" ]; then
      EXPECTED_SHA256="$LOCK_EXPECTED_SOURCE_SHA256"
    fi
    enforce_remote_archive_trust
  fi
  if [ "$ARCHIVE_URL_EXPLICIT" = "1" ] && \
     [ "$SOURCE_REF_EXPLICIT" = "0" ] && [ -z "$SOURCE_DIR" ]; then
    fail "--archive-url requires an explicit --ref during update"
  fi
  if [ "$ROOT_CONFLICT_EXPLICIT" = "0" ]; then
    ROOT_CONFLICT="$LOCK_ROOT_CONFLICT"
  fi
  if [ "$HOOK_CONFLICT_EXPLICIT" = "0" ]; then
    HOOK_CONFLICT="$LOCK_HOOK_CONFLICT"
  fi
  if [ "$ENABLE_GITHOOKS_EXPLICIT" = "0" ]; then
    GIT_HOOKS_ENABLED="$LOCK_GITHOOKS_ENABLED"
    GIT_HOOKS_PREVIOUS_PATH_PRESENT="$LOCK_PREVIOUS_HOOKS_PATH_PRESENT"
    GIT_HOOKS_PREVIOUS_PATH="$LOCK_PREVIOUS_HOOKS_PATH"
  fi
  ROOT_CONFLICT_DECISIONS="$LOCK_ROOT_CONFLICT_DECISIONS"
fi

preflight_required_runtimes
init_tmp_dir

if [ -n "$SOURCE_DIR" ]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
  MANIFEST="$SOURCE_DIR/.beryl/beryl.components.json"
  SOURCE_LABEL="$SOURCE_DIR"
  [ -f "$MANIFEST" ] || fail "missing local manifest: $MANIFEST"
else
  SOURCE_LABEL="$ARCHIVE_URL"
  prepare_remote_release
fi
validate_manifest_sanity
if [ "$UPDATE_MODE" = "1" ]; then
  set_update_context validate lockfile .beryl/lock.json
  validate_lock_selection "invalid existing lockfile" "$LOCK_REQUESTED_COMPONENTS" "$LOCK_COMPONENTS"
fi

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

fi

# Adoption must not assume the installer default profile. Infer only from
# exact, distinctive installed runtime files; ambiguous/partial surfaces are
# later rejected by byte-for-byte adoption validation rather than overwritten.
if [ "$ADOPT_MODE" = "1" ] && [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ]; then
  [ -d "$TARGET_DIR/.beryl" ] && [ ! -L "$TARGET_DIR/.beryl" ] || \
    fail "adoption requires an existing non-symlink .beryl directory"
  if [ -f "$TARGET_DIR/.beryl/driver/run.sh" ]; then
    PROFILE="full"
  elif [ -f "$TARGET_DIR/.beryl/scripts/check.sh" ]; then
    PROFILE="standard"
  elif [ -f "$TARGET_DIR/.beryl/agent/tool-instruction-template.md" ]; then
    PROFILE="minimal"
  else
    fail "adoption could not infer an installed component surface; pass --profile or --components"
  fi
  printf 'beryl: adoption inferred profile %s\n' "$PROFILE"
fi

if [ "$RECOVERY_ACTION" = "restore" ]; then
  if [ -n "$COMPONENTS_CSV" ]; then
    REQUESTED_COMPONENTS="$(split_csv "$COMPONENTS_CSV")"
  else
    REQUESTED_COMPONENTS="$(profile_components "$PROFILE")"
  fi
elif [ "$RECOVERY_ACTION" = "uninstall" ]; then
  if [ -n "$COMPONENTS_CSV" ]; then REQUESTED_COMPONENTS="$(split_csv "$COMPONENTS_CSV")"; else REQUESTED_COMPONENTS="$(profile_components "$PROFILE")"; fi
elif [ "$UPDATE_MODE" = "1" ] && [ "$EXPLICIT_COMPONENT_SELECTION" = "0" ]; then
  REQUESTED_COMPONENTS="$LOCK_REQUESTED_COMPONENTS"
  PROFILE=""
elif [ -n "$COMPONENTS_CSV" ]; then
  REQUESTED_COMPONENTS="$(split_csv "$COMPONENTS_CSV")"
else
  REQUESTED_COMPONENTS="$(profile_components "$PROFILE")"
fi
if [ "$UPDATE_MODE" = "1" ] || [ "$RECOVERY_ACTION" = "restore" ]; then
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
if list_has "$REQUESTED_COMPONENTS" agent-bootstrap; then
  fail "agent-bootstrap is not an installable component; run --bootstrap-agent against a locked target"
fi
if [ "$UPDATE_MODE" = "1" ] && list_has "$LOCK_COMPONENTS" githooks && \
   ! list_has "$RESOLVED_COMPONENTS" githooks; then
  GITHOOKS_REMOVED="1"
fi

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

if [ "$RECOVERY_ACTION" = "uninstall" ]; then
  validate_lock_selection "invalid recovery lockfile" "$RECOVERY_CURRENT_REQUESTED_COMPONENTS" "$RECOVERY_CURRENT_LOCK_COMPONENTS"
  lock_component_sets_equal "$RECOVERY_CURRENT_REQUESTED_COMPONENTS" "$REQUESTED_COMPONENTS" || \
    fail "invalid recovery lockfile: requested components do not match explicit uninstall selection"
  lock_component_sets_equal "$RECOVERY_CURRENT_LOCK_COMPONENTS" "$RESOLVED_COMPONENTS" || \
    fail "invalid recovery lockfile: resolved components do not match explicit uninstall selection"
  validate_lock_managed_surface "invalid recovery lockfile" "$RECOVERY_CURRENT_MANAGED_PATHS" "$RECOVERY_CURRENT_LOCK_COMPONENTS"
fi
if [ "$RECOVERY_ACTION" = "restore" ]; then
  validate_lock_selection "invalid restored backup lockfile" "$RECOVERY_REQUESTED_COMPONENTS" "$RECOVERY_LOCK_COMPONENTS"
  lock_component_sets_equal "$RECOVERY_REQUESTED_COMPONENTS" "$REQUESTED_COMPONENTS" || \
    fail "invalid restored backup lockfile: requested components do not match explicit restore selection"
  lock_component_sets_equal "$RECOVERY_LOCK_COMPONENTS" "$RESOLVED_COMPONENTS" || \
    fail "invalid restored backup lockfile: resolved components do not match explicit restore selection"
  validate_lock_managed_surface "invalid restored backup lockfile" "$RECOVERY_RESTORED_MANAGED_PATHS" "$RECOVERY_LOCK_COMPONENTS"
fi

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

if [ "$RECOVERY_ACTION" = "restore" ] || [ "$RECOVERY_ACTION" = "uninstall" ]; then
  recovery_build_authorized_surface
  if [ "$RECOVERY_ACTION" = "restore" ]; then run_restore_action; else run_uninstall_action; fi
  LIFECYCLE_COMMITTED="1"
  exit 0
fi

if [ "$RECOVERY_ACTION" = "adopt" ]; then
  run_adopt_action
  LIFECYCLE_COMMITTED="1"
  exit 0
fi

if [ "$UPDATE_MODE" = "1" ]; then
  if [ "$LEGACY_LOCK" = "1" ]; then
    # A legacy lock has no file ownership ledger. Do not delete anything from
    # it; only treat files present in the newly staged surface as managed.
    OLD_MANAGED_PATHS="$NEW_MANAGED_PATHS"
  fi
  preflight_githooks_config
  snapshot_update_targets
else
  preflight_initial_install
  preflight_githooks_config
  snapshot_initial_install
fi

APPLIED_MANAGED_PATHS=""
UPDATE_PHASE="apply"
INSTALL_PHASE="apply"
INSTALL_PATH=".beryl"
for rel in $NEW_MANAGED_PATHS; do
  INSTALL_PATH="$rel"
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
INSTALL_PHASE="hook"
INSTALL_PATH="post-install"
run_post_install_hooks
restore_removed_githooks
UPDATE_PHASE="verify"
INSTALL_PHASE="verify"
verify_staged_update
create_update_backup
UPDATE_PHASE="lock"
INSTALL_PHASE="lock"
INSTALL_PATH=".beryl/lock.json"
write_lockfile
LIFECYCLE_COMMITTED="1"
print_first_run_guide
if [ "$INTERACTIVE" = "1" ]; then
  printf 'beryl: agent bootstrap is a standalone post-transaction action. Rerun this installer with:\n'
  printf 'beryl:   --bootstrap-agent --target %s\n' "$TARGET_DIR"
fi
if [ "$UPDATE_MODE" = "1" ]; then
  completion_state="ready"
  [ -z "$ROOT_CONFLICT_DECISIONS" ] || completion_state="ready-with-preserved-external-contracts"
  printf 'beryl: update complete readiness=%s source-ref=%s components=%s updated=%s preserved=%s backup=%s\n' \
    "$completion_state" "$SOURCE_REF" "$(printf '%s' "$RESOLVED_COMPONENTS" | tr '\n' ' ')" "$UPDATED_COUNT" "$PRESERVED_COUNT" \
    "${BACKUP_DIR#${TARGET_DIR}/}"
else
  if [ -n "$ROOT_CONFLICT_DECISIONS" ]; then
    printf "beryl: install complete with preserved external root contracts in %s\n" "$TARGET_DIR"
  else
    printf "beryl: install complete in %s\n" "$TARGET_DIR"
  fi
fi
