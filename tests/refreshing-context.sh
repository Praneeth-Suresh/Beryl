#!/usr/bin/env bash
# Contract and behavior test for the refreshing-context skill (issue #45).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
skill_dir="${REPO_ROOT}/.beryl/agent/skills/refreshing-context"
skill="${skill_dir}/SKILL.md"
drift="${skill_dir}/scripts/context-drift.sh"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-refreshing-context.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require() {
  grep -Fq -- "$2" "$1" || fail "missing required skill contract: $2"
}

[[ -f "${skill}" ]] || fail "missing skill: ${skill}"
[[ -x "${drift}" ]] || fail "context drift script is not executable"
grep -Eq '^name: refreshing-context$' "${skill}" || fail 'skill frontmatter name mismatch'

# Triggers: on request, periodically, and after large repository changes.
require "$skill" 'On a regular cadence'
require "$skill" 'After a large change'

# Evidence before questions, and the finding categories.
require "$skill" 'Do this before asking the developer anything.'
require "$skill" 'context-drift.sh'
for kind in Broken Contradicted Redundant Generic Missing Unverifiable; do
  require "$skill" "| ${kind} |"
done

# The engaging quiz.
require "$skill" '## 2. Quiz The Developer'
require "$skill" 'True or false:'
require "$skill" 'Spot the stale line:'
require "$skill" 'Name it:'
require "$skill" 'Give your recommended answer under each question'
require "$skill" 'one-line score'
require "$skill" 'Do not ask about facts you can check yourself.'

# Removing redundant or misleading context, with approval.
require "$skill" 'Prefer deleting over rewording.'
require "$skill" 'Keep one source for each fact'
require "$skill" 'wait for explicit approval'
require "$skill" 'Never change code to match the context in this workflow.'

grep -Fq '.beryl/agent/skills/refreshing-context/SKILL.md' "${REPO_ROOT}/.beryl/agent/task-routing.md" || \
  fail 'refreshing-context is not routed'
grep -Fq '`refreshing-context`' "${REPO_ROOT}/AGENTS.md" || \
  fail 'generated shim does not list refreshing-context'

# The drift script finds a stale path, ignores live paths and runtime
# artefacts, counts later code changes, and lists unmentioned directories.
fixture="${TMP_DIR}/repo"
mkdir -p "${fixture}/.beryl/agent" "${fixture}/src/billing" "${fixture}/src/identity" "${fixture}/tools"
git -C "${fixture}" init -q
git -C "${fixture}" config user.email beryl-tests@example.invalid
git -C "${fixture}" config user.name 'Beryl tests'
printf 'export {}\n' >"${fixture}/src/billing/index.ts"
printf 'export {}\n' >"${fixture}/src/identity/index.ts"
printf '#!/bin/sh\n' >"${fixture}/tools/run.sh"
cat >"${fixture}/.beryl/agent/architecture.md" <<'MD'
# Architecture

| Context | Public Entry Point |
| --- | --- |
| Billing | `src/billing/index.ts` |
| Payments | `src/payments/index.ts` |

Run `run.sh` to start. The lock is `.beryl/lock.json`. See `src/<context>/index.ts`.
MD
git -C "${fixture}" add -A
git -C "${fixture}" commit -q -m 'initial context'
printf 'export const x = 1\n' >"${fixture}/src/identity/index.ts"
mkdir -p "${fixture}/reports"
printf 'r\n' >"${fixture}/reports/a.csv"
git -C "${fixture}" add -A
git -C "${fixture}" commit -q -m 'code change after context'

"${drift}" "${fixture}" >"${TMP_DIR}/drift.out"
grep -Fq '.beryl/agent/architecture.md: src/payments/index.ts' "${TMP_DIR}/drift.out" || \
  fail 'drift script missed a stale path'
for live in 'src/billing/index.ts' ': run.sh' '.beryl/lock.json' 'src/<context>'; do
  if grep -Fq -- "${live}" "${TMP_DIR}/drift.out"; then
    fail "drift script reported a live, runtime, or placeholder path: ${live}"
  fi
done
grep -Fq '.beryl/agent/architecture.md: last updated' "${TMP_DIR}/drift.out" || \
  fail 'drift script did not report the context file age'
grep -Fq '2 non-Markdown files outside .beryl changed since' "${TMP_DIR}/drift.out" || \
  fail 'drift script miscounted code changes since the context update'
grep -Fxq 'reports/' "${TMP_DIR}/drift.out" || fail 'drift script missed an unmentioned directory'
grep -Fxq 'tools/' "${TMP_DIR}/drift.out" || fail 'drift script missed an unmentioned directory'
if grep -Fxq 'src/' "${TMP_DIR}/drift.out"; then
  fail 'drift script reported a mentioned directory as unmentioned'
fi

# It must not modify the repository it inspects.
[[ -z "$(git -C "${fixture}" status --porcelain)" ]] || fail 'drift script modified the inspected repository'

# It runs cleanly on this repository.
"${drift}" "${REPO_ROOT}" >"${TMP_DIR}/self.out"

printf 'refreshing-context tests passed\n'
