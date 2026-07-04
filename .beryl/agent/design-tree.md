# Design Tree

## Current Design Concept

Beryl is a relocatable hard guarantee layer for agent-ready repositories: canonical instructions, checks, hooks, driver utilities, component profiles, and review contracts live under one `.beryl/` subtree, while only externally mandated root contracts remain at the repository root and are generated or installed from the `.beryl/` source of truth.

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |

## Settled Decisions

| Decision | Choice | Date | ADR |
| --- | --- | --- | --- |

## Pressure Points

- Root instruction shims can drift if `.beryl/agent/scripts/sync-agent-env.sh` cannot write all external tool locations.
- The shell manifest parser depends on the intentionally compact manifest object shape.
- "Hard guarantee" must remain a process claim backed by files, scripts, manifests, and review gates, not a claim that Beryl guarantees correct code or replaces human judgment.

## Recording Rule (Design Tree vs ADR)

Add or update this file when:

- A decision is still evolving.
- You are comparing options before implementation.
- The choice may still change after one or two implementation iterations.

Create an ADR when:

- The decision changes module boundaries, persistence shape, adapter contracts, security model, naming conventions used across contexts, or test strategy.
- Future contributors are likely to revisit the choice without clear repo history.
