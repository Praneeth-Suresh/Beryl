# Architecture

## Bounded Contexts

| Context | Owns | Does Not Own | Public Entry Point |
| --- | --- | --- | --- |
| Beryl Control Plane | Agent instructions, task workflows, deterministic checks, component manifest, installer, optional hooks, and driver prompts under `.beryl/` | Host application source, host test commands beyond configured adapters, and external tool root lookup locations | `.beryl/beryl.components.json`, `install.sh`, `.beryl/scripts/check.sh`, `.beryl/scripts/setup-project.sh` |
| Root Contracts | Files external tools require at fixed root paths: generated instruction shims, GitHub workflow, and `.gitignore` | Canonical instruction content and Beryl implementation files | `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`, `.codex/AGENTS.md`, `.github/workflows/deterministic-checks.yml`, `.gitignore` |
| Agent Context Seeds | Generic project-owned canonical files used when installing Beryl into a target repository | Beryl's own project brief, architecture, design decisions, vocabulary, or ADR history | `.beryl/agent/templates/install/`, `.beryl/agent/scripts/seed-agent-context.sh` |

## Boundary Rules

1. A context may import only another context's public entry point.
2. Internal files of another context are forbidden imports.
3. External APIs, SDKs, and persistence details must be accessed through adapters.
4. Domain logic must not depend directly on HTTP objects, ORM records, UI state, or vendor client types.
5. Beryl-owned implementation files live under `.beryl/`; root files are allowed only when an external tool requires that location.
6. Scripts use `BERYL_ROOT` for Beryl-owned paths and `REPO_ROOT` for host project scans, Git operations, generated root shims, and test manifests.

## Public Interface Rule

Each context exposes one explicit public entry point:

- TypeScript: `src/<context>/index.ts`
- Python: `src/<context>/__init__.py`
- Go: exported symbols in `internal/<context>` via deliberate package API

## Forbidden Import Policy

Record concrete forbidden import patterns here once contexts exist:

- `[from] -> [to/internal/**]`
- `[from] -> [to/infrastructure/**]`

Keep this list small and high-signal. Add rules only after repeated boundary mistakes.

## Delivery Interfaces

- `.beryl/beryl.components.json` is the source of truth for components, profiles, dependencies, selected paths, root contract paths, and post-install hooks.
- `install.sh` is the raw-GitHub entry point. It resolves dependencies, installs only selected manifest paths, optionally prompts for profile/component and agent-bootstrap choices through `--interactive`, seeds generic target-owned agent context, runs declared hooks, and writes `.beryl/lock.json` last.
- `.beryl/scripts/setup-project.sh` is the local onboarding entry point and consumes the same component manifest and seed hook.
- `.beryl/scripts/paths.sh` is the shared boundary between Beryl root and host repo root.
- `.beryl/driver/run.sh` verifies tasks against the task brief and host repository checks. Runtime stack startup is optional and configured through `VERIFY_STACK_MODE`; it is not part of the default Beryl boundary. When `DRIVER_OPTIMIZE_WORKTREES` or `--optimize-worktrees` is enabled, it first delegates to `.beryl/driver/optimize-worktrees.sh` to build and verify a task DAG and prepare parallel-ready task worktrees before the still-sequential task loop starts.
- `.beryl/driver/import-github-issues.sh` imports GitHub issues into `.beryl/driver/tasks/` using the GitHub CLI as the external adapter. It preserves existing unfinished driver state by allocating new task ids around it.
- `.beryl/driver/optimize-worktrees.sh` is the optional driver worktree optimization entry point. It treats agent-proposed DAG JSON as untrusted input, verifies it through `.beryl/driver/lib/worktree_optimizer.py`, and records optimizer state under `.beryl/driver/state/optimization/`.
- Linked GitHub issue finalization is a soft side effect of `.beryl/driver/run.sh` after a task commit succeeds. It writes issue comment/close evidence under `.beryl/driver/state/<task-id>/` and must not make a verified local commit fail because GitHub is unavailable.
