# Design Tree

## Current Design Concept

[One paragraph describing the organizing idea of the system.]

## Open Decisions

| Decision | Options | Current Lean | Why |
| --- | --- | --- | --- |
| [Question] | [A, B, C] | [A] | [Reason] |

## Settled Decisions

| Decision | Choice | Date | ADR |
| --- | --- | --- | --- |
| [Question] | [Choice] | [YYYY-MM-DD] | [ADR link or n/a] |
| Commit-time test selection | Use an affected test gate behind `scripts/check.sh` instead of Husky-only hook logic | 2026-06-25 | [ADR 0002](adr/0002-use-affected-test-gate-for-commit-feedback.md) |
| Project onboarding | Use an interactive setup script with explicit headless-agent fallback | 2026-06-25 | [ADR 0003](adr/0003-use-interactive-setup-script-for-project-onboarding.md) |
| Pre-coding proof points | Require success checks before meaningful redirects or implementation so plans close with measured evidence | 2026-07-02 | n/a |
| Post-run cleanup mode | After long product runs, forbid new features and return one safe extraction slice based on changed-file evidence | 2026-07-02 | n/a |

## Pressure Points

- [Constraint, ambiguity, or tradeoff affecting delivery]

## Recording Rule (Design Tree vs ADR)

Add or update this file when:

- A decision is still evolving.
- You are comparing options before implementation.
- The choice may still change after one or two implementation iterations.

Create an ADR when:

- The decision changes module boundaries, persistence shape, adapter contracts, security model, naming conventions used across contexts, or test strategy.
- Future contributors are likely to revisit the choice without clear repo history.
