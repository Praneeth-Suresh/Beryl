#!/usr/bin/env bash
# Regression test for issue #46: the simplified instruction surface.
# - The installed skill set is exactly the agreed list.
# - Vendored skills keep their upstream licence and are listed in VENDORED.md.
# - Session state, ADR files, and design-tree.md are gone, and nothing tracked
#   tells agents to use them.
# - A fresh install seeds the decision record and none of the removed files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="${REPO_ROOT}/.beryl/agent/skills"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-skill-set.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expected_skills=(
  communicating-with-users
  composing-modules
  creating-illustrations
  frontend-design
  grill-me
  grilling
  initial-build
  maintaining-codebase
  planning
  systematic-debugging
  test-driven-development
  understand-codebase
  using-beryl
  verification-before-completion
)

actual="$(git -C "${REPO_ROOT}" ls-files -- .beryl/agent/skills | sed -n 's#^\.beryl/agent/skills/\([^/]*\)/.*#\1#p' | LC_ALL=C sort -u)"
expected="$(printf '%s\n' "${expected_skills[@]}" | LC_ALL=C sort)"
[[ "${actual}" == "${expected}" ]] || fail "skill set differs from the agreed list:
$(diff <(printf '%s\n' "${expected}") <(printf '%s\n' "${actual}") || true)"

for skill in "${expected_skills[@]}"; do
  [[ -f "${SKILLS}/${skill}/SKILL.md" ]] || fail "missing SKILL.md for ${skill}"
done

# Vendored skills: listed with a full commit SHA and shipped with a licence.
vendored=(systematic-debugging test-driven-development verification-before-completion grill-me grilling frontend-design)
for skill in "${vendored[@]}"; do
  grep -Eq "^\| \`${skill}\` \| <https://github\.com/[^>]+> \| \`[^\`]+\` \| \`[0-9a-f]{40}\` \|" \
    "${SKILLS}/VENDORED.md" || fail "VENDORED.md has no pinned row for ${skill}"
  compgen -G "${SKILLS}/${skill}/LICENSE*" >/dev/null || fail "vendored skill ${skill} has no licence file"
  grep -Fq "${skill}" "${REPO_ROOT}/NOTICE" || fail "NOTICE does not attribute ${skill}"
done
grep -Fq 'Copyright (c) 2025 Jesse Vincent' "${SKILLS}/systematic-debugging/LICENSE" || \
  fail 'superpowers licence text changed'
grep -Fq 'Copyright (c) 2026 Matt Pocock' "${SKILLS}/grill-me/LICENSE" || \
  fail 'mattpocock licence text changed'
grep -Fq 'Apache License' "${SKILLS}/frontend-design/LICENSE.txt" || \
  fail 'frontend-design licence text changed'
grep -Eq '^name: grilling$' "${SKILLS}/grilling/SKILL.md" || fail 'grilling frontmatter changed'

# Every task-routing target and every skill named in the shim must exist.
while IFS= read -r skill_path; do
  [[ -f "${REPO_ROOT}/${skill_path}" ]] || fail "task-routing.md points at a missing skill: ${skill_path}"
done < <(grep -oE '\.beryl/agent/skills/[a-z-]+/SKILL\.md' "${REPO_ROOT}/.beryl/agent/task-routing.md" | sort -u)
while IFS= read -r skill; do
  [[ -d "${SKILLS}/${skill}" ]] || fail "tool-instruction-template.md names a missing skill: ${skill}"
done < <(sed -n 's/^- `\([a-z-]*\)`: .*/\1/p' "${REPO_ROOT}/.beryl/agent/tool-instruction-template.md")

# Removed files stay removed from the tracked source surface.
for removed in .beryl/agent/session-state.md .beryl/agent/design-tree.md .beryl/agent/adr \
  .beryl/agent/templates/install/design-tree.md .beryl/agent/templates/install/adr; do
  [[ -z "$(git -C "${REPO_ROOT}" ls-files -- "${removed}")" ]] || fail "removed path is tracked again: ${removed}"
done

# Nothing tracked, other than vendored upstream text, the explicit legacy
# preserve list, and tests asserting absence, tells agents to use the removed mechanisms or skills.
pattern='session-state|design-tree\.md|\.beryl/agent/adr|skills/(adding-features|debugging|testing-vertical-slices|tracking-entropy|improving-architecture|interview-me|explaining-codebase)/'
if hits="$(git -C "${REPO_ROOT}" grep -n -E "${pattern}" -- . \
  ':(exclude)tests/**' \
  ':(exclude).beryl/beryl.components.json' \
  ':(exclude).beryl/scripts/portability-smoke.sh' \
  ':(exclude).beryl/agent/skills/systematic-debugging/**' \
  ':(exclude).beryl/agent/skills/test-driven-development/**')"; then
  fail "tracked files still reference removed instructions:
${hits}"
fi
# The preserve list keeps legacy target-owned files safe during updates.
for legacy in .beryl/agent/session-state.md .beryl/agent/design-tree.md .beryl/agent/adr/; do
  grep -Fq "\"${legacy}\"" "${REPO_ROOT}/.beryl/beryl.components.json" || \
    fail "updatePreservePaths no longer protects legacy ${legacy}"
done

# The decision record carries a one-line summary for every former ADR.
for n in 0001 0002 0003 0004 0005 0006 0007 0008 0009 0010 0011 0012; do
  grep -Fq "(ADR ${n})" "${REPO_ROOT}/.beryl/agent/architecture.md" || \
    fail "architecture.md has no decision record line for ADR ${n}"
done

# A fresh install seeds the decision record and no removed files.
target="${TMP_DIR}/target"
mkdir -p "${target}"
git -C "${target}" init -q
sh "${REPO_ROOT}/install.sh" --source-dir "${REPO_ROOT}" --target "${target}" \
  --profile minimal >"${TMP_DIR}/install.out"
grep -Fq '## Decision Record' "${target}/.beryl/agent/architecture.md" || \
  fail 'installed architecture.md has no Decision Record section'
for removed in .beryl/agent/design-tree.md .beryl/agent/adr .beryl/agent/session-state.md; do
  [[ ! -e "${target}/${removed}" ]] || fail "fresh install created ${removed}"
done
[[ ! -e "${target}/.gitignore" ]] || ! grep -Fq 'session-state' "${target}/.gitignore" || \
  fail 'fresh install added a session-state ignore rule'
"${target}/.beryl/agent/scripts/agent-doctor.sh" >"${TMP_DIR}/doctor.out"

printf 'skill set tests passed\n'
