# Maintaining Codebase

## Purpose

Turn one request for sustained codebase maintenance into an evidence-led,
repository-wide improvement program. It reduces technical debt without treating
"improve everything" as permission for a risky, unreviewed rewrite.

## Trigger

Use for periodic maintenance, technical-debt reduction, code-quality
improvement, complexity management, or a whole-repository upkeep request.
`tracking-entropy` remains the focused hotspot-analysis skill; this skill owns
the top-level maintenance assessment and prioritisation.

## Assessment

1. Read the repository's architecture, ubiquitous language, testing policy,
   design decisions, ownership rules, and current change state.
2. Gather evidence rather than rating files by intuition: churn and hotspot
   data, dependency state, lint/type/test/build output when configured,
   boundary/import patterns, duplication, complexity indicators, stale docs,
   dead generated assets, security advisories, and recent incident or failure
   evidence. State unavailable evidence and do not invent it.
3. For each finding, name the owning bounded context, evidence, user impact,
   likely root cause, risk level, and the smallest protecting test or check.
4. Score and rank work using impact, likelihood, change cost, and confidence.
   Separate quick safe cleanup from architectural debt, product work, and
   unproven speculation.

## Maintenance program

Produce a compact reviewable program containing:

- a repository health snapshot and an explicit list of evidence gaps;
- a prioritised backlog with risk, ownership, expected benefit, and rollback
  boundary;
- dependency-ordered, behavior-preserving extraction/refactor slices;
- a cadence for repeating the assessment and measurable exit signals;
- test, documentation, security, performance, accessibility, and observability
  follow-ups where evidence supports them.

Do not modify code during the assessment. Present the program and wait for
approval before any implementation. After approval, route each behavior change
through the normal planning/feature or debugging workflow; use
`tracking-entropy` for hotspot evidence and `improving-architecture` only when
the public boundary is demonstrably unclear. Never bundle unrelated cleanup,
weaken tests, claim all debt is removed, or convert a finding into a feature
without separate product approval.

## Output

Use this structure:

```yaml
skill: maintaining-codebase
status: success
health_snapshot: "<evidence-based summary>"
evidence_gaps: ["<unavailable input>"]
priorities:
  - finding: "<problem>"
    bounded_context: "<owner>"
    evidence: "<facts>"
    risk: "<low|medium|high>"
    protecting_check: "<command or test>"
maintenance_slices: ["<dependency-ordered, reviewable change>"]
cadence: "<repeat interval and trigger>"
approval_required_before_implementation: true
```
