# Design Tree

## Current Design Concept

Beryl is a relocatable hard guarantee layer for agent-ready repositories: canonical instructions, checks, hooks, driver utilities, component profiles, and review contracts live under one `.beryl/` subtree, while only externally mandated root contracts remain at the repository root and are generated or installed from the `.beryl/` source of truth.

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |
| Installer parser runtime | POSIX shell parser, `jq`, Python | POSIX shell parser over constrained manifest JSON | Keeps one-line install friction low; revisit if the manifest schema grows beyond the validator's supported shape. |

## Settled Decisions

| Decision | Choice | Date | ADR |
| --- | --- | --- | --- |
| Control-plane layout | Move Beryl-owned implementation files under `.beryl/` and keep only root contracts at fixed external locations. | 2026-07-04 | `.beryl/agent/adr/0004-relocate-control-plane-under-dot-beryl.md` |
| Modular delivery | Use `.beryl/beryl.components.json` plus `install.sh` for profile/component installs without cloning Beryl history. | 2026-07-04 | `.beryl/agent/adr/0005-git-history-free-modular-installer.md` |
| Driver verification | Verify driver tasks from the task brief and host repo checks, with runtime stacks optional instead of mandatory. | 2026-07-04 | `.beryl/agent/adr/0006-use-codebase-driven-driver-verification.md` |
| Product positioning | Position Beryl as the repository hard guarantee layer for agent-ready repositories, adjacent to but distinct from skill packs and runtime harnesses. | 2026-07-04 | N/A |
| Install agent context | Seed target-owned `.beryl/agent/` canonical docs from generic templates instead of copying Beryl's own project docs. | 2026-07-04 | `.beryl/agent/adr/0007-seed-generic-agent-context-on-install.md` |
| GitHub issue import | Import GitHub issues into driver task briefs through a separate importer script that uses GitHub CLI as the adapter, preserves in-progress driver state, and treats copied issue bodies as untrusted context. | 2026-07-06 | N/A |
| GitHub issue finalization | After a linked driver task commits, add a completion comment and attempt to close the GitHub issue as a soft-only side effect recorded in driver state. | 2026-07-06 | N/A |
| Driver worktree optimization | Keep driver task execution sequential by default, but add an opt-in preflight that asks an agent for a task DAG, verifies it deterministically, and prepares task worktrees for parallel-ready waves. | 2026-07-13 | N/A |
| Repository upkeep | Use `RepositoryUpkeep.md` as the tracked guide for idea intake, scratch promotion, maintenance cadence, and upkeep verification instead of relying on ignored `current.md` or hidden chat history. | 2026-07-13 | N/A |
| Supported shell hosts | Support macOS system Bash and Windows Git Bash or WSL for installed scripts; keep native PowerShell limited to downloading the POSIX installer. Verify the supported hosts in GitHub Actions. | 2026-07-15 | N/A |
| Open-source distribution | License Beryl under Apache-2.0, ship `LICENSE` and `NOTICE` in every install surface, and document separate trademark, contribution, support, security, and consulting boundaries. | 2026-08-07 | N/A |
| Initial-build hierarchy lifecycle | Route explicit large or greenfield builds through clarification, hierarchical planning, ratification, and dependency-ordered implementation. Keep `.beryl/agent/hierarchy.md` Git-tracked but transient: create it only after ratification, update it during the build, promote durable knowledge to canonical docs, and delete it only after every node and check passes. | 2026-08-10 | `.beryl/agent/adr/0008-tracked-transient-initial-build-hierarchy.md` |
| Transactional installation updates | Treat `install.sh --update` as a lockfile-required, staged transaction. Track Beryl ownership per file in the lockfile, preserve manifest-declared target-owned paths and unowned content, snapshot mutations for rollback, and retain successful replacements under `.beryl/.updates/`. | 2026-08-11 | `.beryl/agent/adr/0009-transactional-ownership-aware-updates.md` |

## Pressure Points

- Root instruction shims can drift if `.beryl/agent/scripts/sync-agent-env.sh` cannot write all external tool locations.
- The shell manifest parser depends on the intentionally compact manifest object shape.
- GitHub issue imports depend on a locally authenticated `gh` CLI and must not reuse task ids that still have unfinished or stale driver state.
- GitHub issue finalization depends on `gh` and network/auth state, so it must remain observable and soft-only instead of becoming part of the local commit gate.
- Driver worktree optimization depends on untrusted agent DAG output and local Git worktree state; deterministic verification and observable failure files must gate any worktree setup before task implementation starts.
- Repository upkeep depends on maintainers promoting only durable decisions, terms, commands, and review rules into tracked files; scratch notes remain non-authoritative.
- "Hard guarantee" must remain a process claim backed by files, scripts, manifests, and review gates, not a claim that Beryl guarantees correct code or replaces human judgment.
- The initial-build workflow must keep hierarchy progress separate from durable project context: deleting a completed hierarchy must not delete decisions, boundaries, vocabulary, or verification knowledge that future work needs.
- Updates must distinguish Beryl-managed runtime files from target-owned context and configuration. Legacy lockfiles cannot prove prior per-file ownership, so their migration must avoid deletion and keep replacements recoverable.

## Recording Rule (Design Tree vs ADR)

Add or update this file when:

- A decision is still evolving.
- You are comparing options before implementation.
- The choice may still change after one or two implementation iterations.

Create an ADR when:

- The decision changes module boundaries, persistence shape, adapter contracts, security model, naming conventions used across contexts, or test strategy.
- Future contributors are likely to revisit the choice without clear repo history.
