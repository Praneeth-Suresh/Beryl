# ADR 0001: Record Architecture Decisions

## Status

Accepted

## Context

Agent-generated changes require durable, repo-owned memory so future implementation does not depend on hidden chat context.

## Decision

Use ADR files in `.beryl/agent/adr/` for decisions that change architecture boundaries, data shape, adapter contracts, naming conventions across contexts, or test strategy.

## Consequences

- **Benefit:** Future contributors and agents can recover rationale quickly.
- **Tradeoff:** Small overhead when recording durable decisions.
- **Follow-up:** Link new ADRs from `.beryl/agent/design-tree.md` settled decisions.

