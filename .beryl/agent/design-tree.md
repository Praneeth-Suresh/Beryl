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

## Pressure Points

- Root instruction shims can drift if `.beryl/agent/scripts/sync-agent-env.sh` cannot write all external tool locations.
- The shell manifest parser depends on the intentionally compact manifest object shape.
- GitHub issue imports depend on a locally authenticated `gh` CLI and must not reuse task ids that still have unfinished or stale driver state.
- "Hard guarantee" must remain a process claim backed by files, scripts, manifests, and review gates, not a claim that Beryl guarantees correct code or replaces human judgment.

## Recording Rule (Design Tree vs ADR)

Add or update this file when:

- A decision is still evolving.
- You are comparing options before implementation.
- The choice may still change after one or two implementation iterations.

Create an ADR when:

- The decision changes module boundaries, persistence shape, adapter contracts, security model, naming conventions used across contexts, or test strategy.
- Future contributors are likely to revisit the choice without clear repo history.
