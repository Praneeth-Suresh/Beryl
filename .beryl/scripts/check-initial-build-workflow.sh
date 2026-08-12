#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=paths.sh
source "${SCRIPT_DIR}/paths.sh"

SKILL="${BERYL_ROOT}/agent/skills/initial-build/SKILL.md"
ROUTING="${BERYL_ROOT}/agent/task-routing.md"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || fail "missing file: ${path#${REPO_ROOT}/}"
}

require_text() {
  local path="$1"
  local pattern="$2"
  local description="$3"
  grep -Eiq -- "${pattern}" "${path}" || fail "${description}: ${path#${REPO_ROOT}/}"
}

line_for() {
  local path="$1"
  local pattern="$2"
  grep -Einm1 -- "${pattern}" "${path}" | cut -d: -f1
}

require_before() {
  local path="$1"
  local first_pattern="$2"
  local second_pattern="$3"
  local description="$4"
  local first second

  first="$(line_for "${path}" "${first_pattern}" || true)"
  second="$(line_for "${path}" "${second_pattern}" || true)"
  [[ -n "${first}" && -n "${second}" && "${first}" -lt "${second}" ]] || \
    fail "${description}: expected ${first_pattern} before ${second_pattern}"
}

require_file "${SKILL}"
require_file "${ROUTING}"

# These checks intentionally inspect prose markers rather than attempting to
# emulate an LLM. They protect the shipped lifecycle contract deterministically.
require_text "${ROUTING}" 'initial-build' 'initial-build route is not registered'
require_text "${ROUTING}" 'skills/initial-build/SKILL\.md|initial-build.*SKILL' 'initial-build route does not point to its skill'

require_text "${SKILL}" 'clarif|interview|question' 'clarification step is missing'
require_text "${SKILL}" 'ratif|approval|approv' 'user approval/ratification step is missing'
require_before "${SKILL}" 'clarif|interview|question' 'ratif|approval|approv' \
  'clarification must precede ratification'

require_text "${SKILL}" 'hierarchy\.md' 'hierarchy.md lifecycle is missing'
require_before "${SKILL}" 'ratif|approval|approv' 'creat(e|ing|ion).*hierarchy|hierarchy.*creat(e|ing|ion)' \
  'hierarchy creation must follow approval'
require_text "${SKILL}" 'git check-ignore' 'hierarchy ignore verification is missing'
require_text "${SKILL}" 'git add .*hierarchy\.md' 'hierarchy staging requirement is missing'
require_text "${SKILL}" 'git ls-files' 'hierarchy tracked-state verification is missing'
require_text "${SKILL}" 'first.*authoriz(ed|es).*build commit|first build commit.*authoriz' \
  'hierarchy is not required in the first authorized build commit'
require_text "${SKILL}" 'updates.*committed.*implementation slices|commits.*corresponding implementation slices' \
  'hierarchy updates are not committed with implementation slices'

for field in hierarchy dependencies deliverables acceptance status context; do
  require_text "${SKILL}" "${field}" "hierarchy schema is missing ${field}"
done
require_text "${SKILL}" 'context[ -_]*targets|targets?.*context' 'hierarchy schema is missing context targets'

require_text "${SKILL}" 'resume|continu(e|ation).*existing' 'existing hierarchy resume behavior is missing'
require_text "${SKILL}" 'promot(e|ing|ion).*durable|durable.*promot(e|ing|ion)|canonical.*context' \
  'durable context promotion is missing'
require_text "${SKILL}" 'all.*(node|subtask)|every.*(node|subtask)' 'completion does not require every hierarchy node'
require_text "${SKILL}" 'all.*check|every.*check|required.*check' 'completion does not require required checks'
require_text "${SKILL}" '(delet|remov).*hierarchy\.md|hierarchy\.md.*(delet|remov)' \
  'completion does not delete hierarchy.md'
require_text "${SKILL}" 'deletion.*same authorized final.*commit|deletion.*committed.*final' \
  'hierarchy deletion is not committed with final durable promotions'
require_text "${SKILL}" 'ordinary|normal|feature' 'ordinary-work behavior is not described'
require_text "${SKILL}" 'must not|do not|does not|without' 'ordinary-work exclusion is not explicit'
require_text "${SKILL}" 'hierarchy\.md' 'ordinary-work exclusion does not mention hierarchy.md'

printf 'check-initial-build-workflow: PASS\n'
