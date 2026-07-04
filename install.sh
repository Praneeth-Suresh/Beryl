#!/bin/sh
set -eu

INSTALLER_VERSION="1"
DEFAULT_REF="main"
DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/praneeth/Beryl/main"
DEFAULT_ARCHIVE_URL="https://codeload.github.com/praneeth/Beryl/tar.gz/main"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  sh install.sh [--profile minimal|standard|full] [--components a,b] [--target DIR]

Options:
  --profile NAME              Install a named profile. Default: standard.
  --components a,b            Install explicit components plus dependencies.
  --target DIR                Install into DIR. Default: current directory.
  --source-dir DIR            Copy from a local Beryl checkout. Used by tests.
  --ref REF                   GitHub ref for remote install. Default: main.
  --raw-base-url URL          Raw GitHub base URL for install.sh and manifest.
  --archive-url URL           GitHub codeload tarball URL.
  --root-conflict POLICY      fail, overwrite, or skip root files. Default: fail.
  --enable-githooks           Set core.hooksPath=.beryl/githooks when installed.
  --dry-run                   Print resolved components and paths only.
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

download_manifest() {
  mkdir -p "$TMP_DIR"
  MANIFEST="$TMP_DIR/beryl.components.json"
  ensure_https "$RAW_BASE_URL"
  printf "beryl: fetching manifest from %s/.beryl/beryl.components.json\n" "$RAW_BASE_URL"
  curl -fsSL "$RAW_BASE_URL/.beryl/beryl.components.json" -o "$MANIFEST"
}

copy_local_path() {
  rel="$1"
  src="${SOURCE_DIR%/}/$rel"
  dst="${TARGET_DIR%/}/$rel"

  [ -e "$src" ] || fail "source path missing: $rel"
  mkdir -p "$(dirname "$dst")"

  case "$rel" in
    .beryl/*)
      rm -rf "$dst"
      cp -R "$src" "$dst"
      ;;
    *)
      if [ -e "$dst" ] && ! cmp -s "$src" "$dst" 2>/dev/null; then
        case "$ROOT_CONFLICT" in
          fail) fail "root file conflict: $rel (use --root-conflict overwrite or skip)" ;;
          skip) printf "beryl: skipped existing root file %s\n" "$rel"; return 0 ;;
          overwrite) ;;
        esac
      fi
      cp -R "$src" "$dst"
      ;;
  esac
  printf "beryl: installed %s\n" "$rel"
}

extract_remote_paths() {
  ensure_https "$ARCHIVE_URL"
  archive="$TMP_DIR/beryl.tar.gz"
  stage="$TMP_DIR/stage"
  mkdir -p "$stage"

  printf "beryl: fetching archive %s\n" "$ARCHIVE_URL"
  curl -fsSL "$ARCHIVE_URL" -o "$archive"
  prefix="$(tar -tzf "$archive" | sed -n '1s#/$##p; q')"
  [ -n "$prefix" ] || fail "could not detect archive prefix"

  for rel in $INSTALL_PATHS; do
    tar -xzf "$archive" -C "$stage" --strip-components=1 "${prefix}/${rel%/}" 2>/dev/null || \
      tar -xzf "$archive" -C "$stage" --strip-components=1 "${prefix}/${rel}" 2>/dev/null || \
      fail "archive path missing: $rel"
  done

  for rel in $INSTALL_PATHS; do
    SOURCE_DIR="$stage"
    copy_local_path "$rel"
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
      case "$hook" in
        seed-agent-context)
          if [ -x "$TARGET_DIR/.beryl/agent/scripts/seed-agent-context.sh" ]; then
            printf "beryl: running post-install hook: .beryl/agent/scripts/seed-agent-context.sh\n"
            (cd "$TARGET_DIR" && BERYL_AGENT_TEMPLATE_CONFLICT="${BERYL_AGENT_TEMPLATE_CONFLICT:-skip}" ./.beryl/agent/scripts/seed-agent-context.sh)
          fi
          ;;
        sync-agent-env)
          if [ -x "$TARGET_DIR/.beryl/agent/scripts/sync-agent-env.sh" ]; then
            printf "beryl: running post-install hook: .beryl/agent/scripts/sync-agent-env.sh\n"
            (cd "$TARGET_DIR" && BERYL_SHIM_CONFLICT="$ROOT_CONFLICT" ./.beryl/agent/scripts/sync-agent-env.sh)
          fi
          ;;
        update-test-manifest)
          if [ -x "$TARGET_DIR/.beryl/scripts/update-test-manifest.sh" ]; then
            printf "beryl: running post-install hook: .beryl/scripts/update-test-manifest.sh\n"
            (cd "$TARGET_DIR" && ./.beryl/scripts/update-test-manifest.sh)
          fi
          ;;
        enable-githooks)
          if [ "$ENABLE_GITHOOKS" = "1" ] && command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            printf "beryl: running post-install hook: git config core.hooksPath .beryl/githooks\n"
            git -C "$TARGET_DIR" config core.hooksPath .beryl/githooks
          else
            printf "beryl: skipped githook enablement (pass --enable-githooks inside a Git repo)\n"
          fi
          ;;
      esac
    done
  done
}

write_lockfile() {
  mkdir -p "$TARGET_DIR/.beryl"
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
    printf "\n}\n"
  } >"$TARGET_DIR/.beryl/lock.json"
  printf "beryl: wrote .beryl/lock.json\n"
}

PROFILE="standard"
COMPONENTS_CSV=""
TARGET_DIR="$(pwd)"
SOURCE_DIR=""
SOURCE_REF="$DEFAULT_REF"
RAW_BASE_URL="$DEFAULT_RAW_BASE_URL"
ARCHIVE_URL="$DEFAULT_ARCHIVE_URL"
ROOT_CONFLICT="fail"
ENABLE_GITHOOKS="0"
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
    --profile)
      [ "$#" -ge 2 ] || fail "--profile requires a value"
      PROFILE="$2"
      shift 2
      ;;
    --profile=*)
      PROFILE="${1#--profile=}"
      shift
      ;;
    --components)
      [ "$#" -ge 2 ] || fail "--components requires a value"
      COMPONENTS_CSV="$2"
      PROFILE=""
      shift 2
      ;;
    --components=*)
      COMPONENTS_CSV="${1#--components=}"
      PROFILE=""
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
      RAW_BASE_URL="https://raw.githubusercontent.com/praneeth/Beryl/$SOURCE_REF"
      ARCHIVE_URL="https://codeload.github.com/praneeth/Beryl/tar.gz/$SOURCE_REF"
      shift 2
      ;;
    --ref=*)
      SOURCE_REF="${1#--ref=}"
      RAW_BASE_URL="https://raw.githubusercontent.com/praneeth/Beryl/$SOURCE_REF"
      ARCHIVE_URL="https://codeload.github.com/praneeth/Beryl/tar.gz/$SOURCE_REF"
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

mkdir -p "$TARGET_DIR"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

if [ -n "$SOURCE_DIR" ]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
  MANIFEST="$SOURCE_DIR/.beryl/beryl.components.json"
  SOURCE_LABEL="$SOURCE_DIR"
  [ -f "$MANIFEST" ] || fail "missing local manifest: $MANIFEST"
else
  SOURCE_LABEL="$ARCHIVE_URL"
  download_manifest
fi

if [ -n "$COMPONENTS_CSV" ]; then
  REQUESTED_COMPONENTS="$(split_csv "$COMPONENTS_CSV")"
else
  REQUESTED_COMPONENTS="$(profile_components "$PROFILE")"
fi

EXISTING_COMPONENTS="$(existing_lock_components)"
ALL_COMPONENTS="$(printf "%s\n%s\n" "$REQUESTED_COMPONENTS" "$EXISTING_COMPONENTS" | sed '/^$/d' | awk '!seen[$0]++')"
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

printf "beryl: installer version %s\n" "$INSTALLER_VERSION"
printf "beryl: source ref %s\n" "$SOURCE_REF"
printf "beryl: resolved components: %s\n" "$(printf "%s" "$RESOLVED_COMPONENTS" | tr '\n' ' ')"

if [ "$DRY_RUN" = "1" ]; then
  printf "beryl: install paths:\n"
  printf "%s\n" "$INSTALL_PATHS" | sed 's/^/  /'
  exit 0
fi

if [ -n "$SOURCE_DIR" ]; then
  for rel in $INSTALL_PATHS; do
    copy_local_path "$rel"
  done
else
  extract_remote_paths
fi

chmod +x "$TARGET_DIR"/.beryl/scripts/*.sh 2>/dev/null || true
chmod +x "$TARGET_DIR"/.beryl/agent/scripts/*.sh 2>/dev/null || true
chmod +x "$TARGET_DIR"/.beryl/githooks/pre-commit 2>/dev/null || true

run_post_install_hooks
write_lockfile
printf "beryl: install complete in %s\n" "$TARGET_DIR"
