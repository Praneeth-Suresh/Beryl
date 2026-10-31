#!/usr/bin/env bash
# Read-only report that helps the refreshing-context skill find stale context.
#
# Usage: context-drift.sh [REPO_ROOT]
#
# Prints three sections:
#   1. Repository paths named in the context files that no longer exist.
#   2. Context files that are unchanged while a lot of code changed after them.
#   3. Top-level directories that no context file mentions.
# The output is a list of leads for a human conversation, not a verdict.
set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${REPO_ROOT}"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'context-drift: %s is not a Git work tree\n' "${REPO_ROOT}" >&2
  exit 1
}

# Only the project-owned context files. Beryl-managed files such as
# agent-rules.md are replaced by updates and describe Beryl itself.
CONTEXT_FILES=()
for file in project-brief.md architecture.md ubiquitous-language.md testing-policy.md; do
  [[ -f ".beryl/agent/${file}" && ! -L ".beryl/agent/${file}" ]] && CONTEXT_FILES+=(".beryl/agent/${file}")
done
# Module-level context files, when the repository has sub-module agents.
while IFS= read -r file; do
  CONTEXT_FILES+=("${file}")
done < <(git ls-files -- '*/agent/project-brief.md' '*/agent/architecture.md' \
  '*/agent/ubiquitous-language.md' '*/agent/testing-policy.md' | grep -v '^\.beryl/' || true)
((${#CONTEXT_FILES[@]} > 0)) || {
  printf 'context-drift: no context files found under .beryl/agent/\n' >&2
  exit 1
}

# Paths that Beryl or the host project creates at runtime, and generic
# placeholders used in instructions, are not stale when absent.
is_runtime_path() {
  case "$1" in
    .beryl/lock.json|.beryl/.updates/*|.beryl/artifacts/*|.beryl/driver/state/*|state/*) return 0 ;;
    .beryl/agent/hierarchy.md|hierarchy.md|current.md|.env|.env.*) return 0 ;;
    agent/*) return 0 ;; # module-relative paths in module-routing.md
  esac
  return 1
}

TRACKED_FILES="$(git ls-files)"
path_exists() {
  local path="$1" base
  for base in '' .beryl/ .beryl/agent/ .beryl/scripts/ .beryl/agent/scripts/; do
    [[ -e "${base}${path}" ]] && return 0
  done
  # A bare file name counts when some tracked file has that name.
  if [[ "${path}" != */* ]] && printf '%s\n' "${TRACKED_FILES}" | grep -qE "(^|/)${path//./\\.}\$"; then
    return 0
  fi
  return 1
}

printf '== Paths named in context files that do not exist\n'
missing=0
for file in "${CONTEXT_FILES[@]}"; do
  # Backticked tokens that look like repository paths: contain a slash or a
  # file extension, and no placeholders, globs, variables, or spaces.
  while IFS= read -r token; do
    path="${token#./}"
    case "${path}" in
      ''|/*|~*|http*|*'['*|*'<'*|*'{'*|*'$'*|*'*'*|*' '*|*'|'*) continue ;;
    esac
    [[ "${path}" == */* || "${path}" == *.* ]] || continue
    [[ "${path}" == *[a-zA-Z]* ]] || continue
    # Command lines and flags are not paths.
    [[ "${path}" == -* ]] && continue
    is_runtime_path "${path}" && continue
    if ! path_exists "${path}"; then
      printf '%s: %s\n' "${file}" "${path}"
      missing=$((missing + 1))
    fi
  done < <(grep -oE '`[^`]+`' "${file}" | tr -d '`' | sed 's/:[0-9][0-9]*$//' | sort -u)
done
((missing > 0)) || printf '(none)\n'

printf '\n== Context files and code changes made since each was last updated\n'
for file in "${CONTEXT_FILES[@]}"; do
  last="$(git log -1 --format=%H -- "${file}" 2>/dev/null || true)"
  if [[ -z "${last}" ]]; then
    printf '%s: not committed yet\n' "${file}"
    continue
  fi
  changed="$(git diff --name-only "${last}" HEAD -- . ':(exclude).beryl/**' ':(exclude)*.md' | wc -l | tr -d ' ')"
  printf '%s: last updated %s; %s non-Markdown files outside .beryl changed since\n' \
    "${file}" "$(git log -1 --format=%as "${last}")" "${changed}"
done

printf '\n== Top-level directories no context file mentions\n'
unmentioned=0
while IFS= read -r dir; do
  [[ -n "${dir}" ]] || continue
  case "${dir}" in .*) continue ;; esac
  if ! grep -qF -- "${dir}" "${CONTEXT_FILES[@]}"; then
    printf '%s/\n' "${dir}"
    unmentioned=$((unmentioned + 1))
  fi
done < <(git ls-files | sed -n 's#^\([^/]*\)/.*#\1#p' | sort -u)
((unmentioned > 0)) || printf '(none)\n'
