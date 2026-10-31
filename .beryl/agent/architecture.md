# Architecture

## Bounded Contexts

| Context | Owns | Does Not Own | Public Entry Point |
| --- | --- | --- | --- |
| Beryl Control Plane | Agent instructions, task workflows, deterministic checks, component manifest, installer, optional hooks, and driver prompts under `.beryl/` | Host application source, host test commands beyond configured adapters, and external tool root lookup locations | `.beryl/beryl.components.json`, `install.sh`, `.beryl/scripts/check.sh`, `.beryl/scripts/setup-project.sh` |
| Root Contracts | Files external tools require at fixed root paths: generated instruction shims, GitHub workflow, and `.gitignore` | Canonical instruction content and Beryl implementation files | `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`, `.codex/AGENTS.md`, `.github/workflows/deterministic-checks.yml`, `.gitignore` |
| Agent Context Seeds | Generic project-owned canonical files used when installing Beryl into a target repository | Beryl's own project brief, architecture, design decisions, vocabulary, or ADR history | `.beryl/agent/templates/install/`, `.beryl/agent/scripts/seed-agent-context.sh` |
| Project Legal and Community | Apache-2.0 license and notice, public contribution, trademark-use, support, security, and consulting policies | Beryl control-plane behavior and host-project legal policies | `LICENSE`, `NOTICE`, `TRADEMARKS.md`, `CONTRIBUTING.md`, `SUPPORT.md`, `SECURITY.md`, `SERVICES.md` |

## Boundary Rules

1. A context may import only another context's public entry point.
2. Internal files of another context are forbidden imports.
3. External APIs, SDKs, and persistence details must be accessed through adapters.
4. Domain logic must not depend directly on HTTP objects, ORM records, UI state, or vendor client types.
5. Beryl-owned implementation files live under `.beryl/`; root files are allowed only for external-tool contracts or project legal and community documents.
6. Scripts use `BERYL_ROOT` for Beryl-owned paths and `REPO_ROOT` for host project scans, Git operations, and generated root shims.

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
- `LICENSE` and `NOTICE` are part of every agent-core install surface so downstream recipients receive the Apache-2.0 terms and required attribution notices with Beryl.
- `install.sh` owns initial install, lockfile-required `--update`, `--restore`, `--uninstall`, `--adopt-existing`, and standalone `--bootstrap-agent`. Remote lifecycle sources require a full 40-character commit SHA and trusted archive SHA-256. The lock persists that digest as `expectedSourceSha256`; remote updates reuse it only when no replacement source is selected, and refuse missing/mismatched archive proof. Before `mkdir`, `cd`, or target mutation, the engine lexically validates the target and every existing ancestor and destination leaf without following symbolic links. Its ownership ledger records state and rollback boundaries, but is not deletion authority: normal update preserves deselected ambiguous paths and removes them from Beryl ownership. Explicit selection authorizes destructive recovery: uninstall requires `--profile`/`--components`; restore requires historical selection and current selection before current-only removal. It writes `.beryl/lock.json` only after candidate-lock readiness and post-commit readiness both succeed.
- `.beryl/scripts/setup-project.sh` is the local interactive/noninteractive onboarding frontend. It collects choices and delegates one normalized request to `install.sh`; it does not independently copy files, write locks, mutate hooks, initialize Git, or alter Git configuration.
- Restore applies a retained snapshot only after current-source verification (using `--current-source-dir` when needed), explicit historical/current selection, and remote digest/ref proof before fetch. Uninstall removes only explicitly selected, unchanged digest-proven Beryl paths and restores ledgered Git configuration. Adoption records only an identical unlocked managed surface; with no selection, it infers only minimal, standard, or full from distinctive files and refuses partial/ambiguous state. All refuse ambiguous state rather than widening ownership.
- `beryl-bootstrap.sh` is the independently trusted remote-release selector. It embeds the release public key, verifies fixed signed metadata and expiry with OpenSSL, derives the codeload URL from the signed immutable SHA, verifies the archive digest, and executes only the installer extracted from that archive. Its private signing key is outside repository and CI custody; pinned `install.sh --ref` plus `--expected-sha256` remains the recovery interface.
- External coding-agent bootstrap is explicit post-transaction behavior. Beryl cannot guarantee rollback of external-agent mutations, so bootstrap is a standalone action whose result is reported separately from lifecycle success.
- `.beryl/scripts/paths.sh` is the shared boundary between Beryl root and host repo root.
- `.beryl/driver/run.sh` verifies tasks against the task brief and host repository checks. Runtime stack startup is optional and configured through `VERIFY_STACK_MODE`; it is not part of the default Beryl boundary. When `DRIVER_OPTIMIZE_WORKTREES` or `--optimize-worktrees` is enabled, it first delegates to `.beryl/driver/optimize-worktrees.sh` to build and verify a task DAG and prepare parallel-ready task worktrees before the still-sequential task loop starts.
- `.beryl/driver/import-github-issues.sh` imports GitHub issues into `.beryl/driver/tasks/` using the GitHub CLI as the external adapter. It preserves existing unfinished driver state by allocating new task ids around it.
- `.beryl/driver/optimize-worktrees.sh` is the optional driver worktree optimization entry point. It treats agent-proposed DAG JSON as untrusted input, verifies it through `.beryl/driver/lib/worktree_optimizer.py`, and records optimizer state under `.beryl/driver/state/optimization/`.
- Linked GitHub issue finalization is a soft side effect of `.beryl/driver/run.sh` after a task commit succeeds. It writes issue comment/close evidence under `.beryl/driver/state/<task-id>/` and must not make a verified local commit fail because GitHub is unavailable.
- `.beryl/agent/skills/initial-build/SKILL.md` is the public workflow entry point for explicit large or greenfield application builds. It owns clarification, repository discovery, hierarchical planning, ratification, dependency-ordered implementation, context promotion, and completion rules while remaining model- and tool-neutral.
- `.beryl/agent/skills/understand-codebase/SKILL.md` is the public read-only codebase-teaching entry point. Its renderer accepts structured content only and writes optional offline artifacts under ignored `.beryl/artifacts/understanding/`; inspected repository content remains passive data and cannot determine artifact scripts, links, or commands.
- `.beryl/agent/skills/composing-modules/SKILL.md` is the public dependency-research entry point. It owns evidence collection and a reliability recommendation only; package-manager, clone, manifest, lockfile, and import mutations remain in the approved feature workflow.
- `.beryl/agent/skills/maintaining-codebase/SKILL.md` is the public whole-repository maintenance-assessment entry point. It owns evidence gathering and a prioritised program, while implementation remains in the normal approved feature/debugging boundaries.
- `.beryl/agent/skills/simplifying-code/SKILL.md` is the public entry point for simplifying one module or area. It finds complexity from evidence, proposes behavior-preserving changes, and applies one approved change at a time behind protecting tests.
- `.beryl/agent/hierarchy.md` is a Git-tracked, build-scoped lifecycle artifact. It is created only after an initial-build plan is ratified, is authoritative for active node order and progress, resumes an interrupted build when present, and is deleted only after all nodes and checks pass and durable context has been promoted.

### Initial Build Lifecycle Boundary

The initial-build workflow is part of the Beryl Control Plane. It may read host-project files for discovery and may edit host-project source through the normal feature workflow after ratification, but its planning state has one explicit repository interface: `.beryl/agent/hierarchy.md`.

The hierarchy schema must identify each node's stable id, parent, dependencies, deliverable, acceptance checks, status, and canonical context targets. Node progress, sequencing notes, and temporary rationale stay in the hierarchy; settled scope, architectural boundaries, terminology, and durable verification rules are promoted to the relevant canonical files before completion. The workflow must not create a hierarchy for ordinary feature work.

## Design Concept

Beryl is a relocatable hard guarantee layer for agent-ready repositories: canonical instructions, checks, hooks, driver utilities, component profiles, and review contracts live under one `.beryl/` subtree, while only externally mandated root contracts remain at the repository root and are generated or installed from the `.beryl/` source of truth.

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |
| Installer parser runtime | POSIX shell parser, `jq`, Python | POSIX shell parser over constrained manifest JSON | Keeps one-line install friction low; revisit if the manifest schema grows beyond the validator's supported shape. |

## Decision Record

One line per settled decision: the date, the choice, and the reason. Add a line when a decision changes boundaries, data shape, adapter contracts, security model, shared naming, or test strategy. Earlier decisions were recorded as ADRs 0001 to 0012; their full text is in Git history.

- 2026-05-02 (ADR 0001): Keep durable decisions in repository files, not chat history, so agents and contributors can recover the reasoning.
- 2026-06-25 (ADR 0002): Use `check-affected.sh` with `affected-tests.conf` from the existing pre-commit hook instead of Husky, so commits run related tests without a Node dependency.
- 2026-06-25 (ADR 0003): Make `setup-project.sh` the guided onboarding command, with an explicit opt-in AI fallback, to reduce manual setup errors.
- 2026-07-04 (ADR 0004): Move Beryl-owned files under `.beryl/` and keep only root contracts at fixed paths, separating `BERYL_ROOT` from `REPO_ROOT` to avoid collisions with host projects.
- 2026-07-04 (ADR 0005): Install selected components from `beryl.components.json` through `install.sh` without cloning Beryl history, so behavior is defined once.
- 2026-07-04 (ADR 0006): Verify driver tasks against the task brief and host checks, with runtime stack startup optional through `VERIFY_STACK_MODE`, so non-web repositories work.
- 2026-07-04 (ADR 0007): Seed target-owned context from generic templates on install instead of copying Beryl's own project docs.
- 2026-07-04: Position Beryl as the repository hard guarantee layer, adjacent to but distinct from skill packs and runtime harnesses.
- 2026-07-06: Import GitHub issues into driver task briefs through a separate `gh`-based importer that preserves in-progress driver state and treats issue bodies as untrusted.
- 2026-07-06: After a linked driver task commits, comment on and close the GitHub issue as a soft side effect that cannot fail the local commit.
- 2026-07-13: Keep driver execution sequential by default, with an opt-in preflight that verifies an agent-proposed task DAG and prepares parallel-ready worktrees.
- 2026-07-13: Use `RepositoryUpkeep.md` as the tracked guide for idea intake and maintenance cadence instead of ignored scratch files.
- 2026-07-15: Support macOS system Bash and Windows Git Bash or WSL for installed scripts, verified in GitHub Actions; native PowerShell only downloads the installer.
- 2026-08-07: License Beryl under Apache-2.0 and ship `LICENSE` and `NOTICE` in every install surface.
- 2026-08-10 (ADR 0008): Keep `.beryl/agent/hierarchy.md` Git-tracked but transient during an initial build, created after ratification and deleted after every node passes, so large builds are resumable without leaving progress noise in canonical docs.
- 2026-08-11 (ADR 0009): Make updates transactional and ownership-aware, with a file-level managed-path ledger, preserved target-owned paths, retained backups, and full rollback on failure.
- 2026-08-13 (ADR 0010): `install.sh` is the single lifecycle engine for install, update, restore, uninstall, adoption, and standalone bootstrap, using no-follow path validation, one mutation ledger, candidate-lock readiness before the lock is replaced, and a ledger that is never deletion authority on its own.
- 2026-08-20 (ADR 0011): Select remote releases through an independently trusted `beryl-bootstrap.sh` that verifies signed release metadata and the archive digest before running the archive's installer; the signing key stays outside the repository and CI.
- 2026-09-29 (ADR 0012): Render optional understanding artifacts only from structured, escaped data with no network dependencies, under ignored `.beryl/artifacts/understanding/`, so a read-only teaching workflow cannot execute repository content.
- 2026-09-29: Require evidence thresholds, alternatives, and explicit package-and-version approval before adopting a dependency.
- 2026-09-29: Provide a maintenance-assessment workflow that produces an evidence-backed, dependency-ordered program while keeping normal approval gates.
- 2026-10-31: Remove the SHA test manifest; test changes are reviewed in the diff, and CI runs every tracked `tests/*.sh`.
- 2026-10-31: Remove the session state file, the ADR directory, and the design tree file; durable decisions live in this file as one-line entries.
- 2026-10-31: Add `simplifying-code` for module-level complexity reduction, separate from the whole-repository `maintaining-codebase` assessment, so refactors stay small, evidence-led, and behavior-preserving.
- 2026-10-31: Replace general coding skills with unmodified, licensed upstream skills listed in `.beryl/agent/skills/VENDORED.md`, and keep Beryl-written skills for what is specific to Beryl or what models do poorly, such as communication and illustrations.

## Pressure Points

- Root instruction shims can drift if `.beryl/agent/scripts/sync-agent-env.sh` cannot write all external tool locations.
- The shell manifest parser depends on the intentionally compact manifest object shape.
- GitHub issue imports depend on a locally authenticated `gh` CLI and must not reuse task ids that still have unfinished or stale driver state.
- GitHub issue finalization depends on `gh` and network/auth state, so it must remain observable and soft-only instead of becoming part of the local commit gate.
- Driver worktree optimization depends on untrusted agent DAG output and local Git worktree state; deterministic verification and observable failure files must gate any worktree setup before task implementation starts.
- "Hard guarantee" must remain a process claim backed by files, scripts, manifests, and review gates, not a claim that Beryl guarantees correct code or replaces human judgment.
- The initial-build workflow must keep hierarchy progress separate from durable project context: deleting a completed hierarchy must not delete decisions, boundaries, vocabulary, or verification knowledge that future work needs.
- Updates must distinguish Beryl-managed runtime files from target-owned context and configuration. Legacy lockfiles cannot prove prior per-file ownership, so their migration must avoid deletion and keep replacements recoverable.
- Vendored skills drift from upstream over time. Refresh them by copying a newer upstream commit, never by editing in place.
