#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../scripts/paths.sh
source "${SCRIPT_DIR}/../../scripts/paths.sh"

SKILLS_ROOT="${BERYL_ROOT}/agent/skills"

fail() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  .beryl/agent/scripts/add-skill.sh --list
  .beryl/agent/scripts/add-skill.sh <skill-name> --from <source> [--force]

Ingest a skill into .beryl/agent/skills/<skill-name>/SKILL.md so it lives
with the repository instead of with any one coding agent.

Arguments:
  <skill-name>     Kebab-case skill name (e.g. reviewing-migrations).
  --from <source>  One of:
                     - a local directory containing SKILL.md (copied whole,
                       including supporting files)
                     - a local markdown file (installed as SKILL.md)
                     - an https:// URL to a raw markdown file
  --force          Replace an existing skill of the same name.
  --list           List installed skills and their purposes.

After installing, register the skill where agents discover it:
  1. Add a routing or supporting-skill entry in .beryl/agent/task-routing.md.
  2. Mention it in .beryl/agent/tool-instruction-template.md if every agent
     session should know about it.
  3. Rerun .beryl/agent/scripts/sync-agent-env.sh to regenerate tool shims.
USAGE
}

list_skills() {
  local dir name title
  printf "%-28s %s\n" "SKILL" "TITLE"
  printf -- '---------------------------------------------------------------\n'
  for dir in "${SKILLS_ROOT}"/*/; do
    [[ -f "${dir}SKILL.md" ]] || continue
    name="$(basename "${dir}")"
    title="$(sed -n 's/^# *//p' "${dir}SKILL.md" | head -n1)"
    printf "%-28s %s\n" "${name}" "${title:-<no title>}"
  done
}

validate_name() {
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] \
    || fail "skill name must be kebab-case (lowercase letters, digits, hyphens): $1"
}

validate_skill_md() {
  local file="$1"
  [[ -s "${file}" ]] || fail "skill file is empty: ${file}"
  head -n1 "${file}" | grep -qE '^# ' \
    || fail "SKILL.md must start with a '# <Title>' heading: ${file}"
}

fetch_https() {
  case "$1" in
    https://*) ;;
    *) fail "remote skill sources must use HTTPS: $1" ;;
  esac
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 3 \
    -fsSL "$1" -o "$2"
}

print_next_steps() {
  local name="$1"
  printf "add-skill: installed .beryl/agent/skills/%s/SKILL.md\n" "${name}"
  cat <<NEXT
add-skill: next steps to make agents discover it:
  1. Register '${name}' in .beryl/agent/task-routing.md (Intent Map or
     Supporting Skill Escalation).
  2. Mention it in .beryl/agent/tool-instruction-template.md if every agent
     session should load it, then rerun .beryl/agent/scripts/sync-agent-env.sh.
  3. Run ./.beryl/scripts/check.sh.
NEXT
}

MODE=""
NAME=""
SOURCE=""
FORCE=0

while (($# > 0)); do
  case "$1" in
    --list) MODE="list"; shift ;;
    --from)
      [[ $# -ge 2 ]] || fail "--from requires a value"
      SOURCE="$2"; shift 2 ;;
    --from=*) SOURCE="${1#--from=}"; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) fail "unknown argument: $1" ;;
    *)
      [[ -z "${NAME}" ]] || fail "unexpected extra argument: $1"
      NAME="$1"; shift ;;
  esac
done

if [[ "${MODE}" == "list" ]]; then
  list_skills
  exit 0
fi

[[ -n "${NAME}" ]] || { usage >&2; exit 1; }
[[ -n "${SOURCE}" ]] || fail "missing --from <source>"
validate_name "${NAME}"

dest="${SKILLS_ROOT}/${NAME}"
if [[ -e "${dest}" && "${FORCE}" -ne 1 ]]; then
  fail "skill already exists: ${NAME} (use --force to replace)"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/beryl-add-skill.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT INT TERM

if [[ -d "${SOURCE}" ]]; then
  [[ -f "${SOURCE}/SKILL.md" ]] || fail "source directory has no SKILL.md: ${SOURCE}"
  cp -R "${SOURCE}/." "${tmp}/skill"
elif [[ -f "${SOURCE}" ]]; then
  mkdir -p "${tmp}/skill"
  cp "${SOURCE}" "${tmp}/skill/SKILL.md"
else
  case "${SOURCE}" in
    http://*|https://*)
      mkdir -p "${tmp}/skill"
      fetch_https "${SOURCE}" "${tmp}/skill/SKILL.md"
      ;;
    *)
      fail "source not found (expected a directory, file, or https URL): ${SOURCE}"
      ;;
  esac
fi

validate_skill_md "${tmp}/skill/SKILL.md"

mkdir -p "${SKILLS_ROOT}"
rm -rf "${dest}"
cp -R "${tmp}/skill" "${dest}"
print_next_steps "${NAME}"
