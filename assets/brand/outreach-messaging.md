# Beryl Outreach Messaging

## Positioning

Beryl is the hard guarantee layer for agent-ready repositories.

It does not try to be the smartest agent runtime or the largest skill pack. It prepares a repository so agent work has a visible contract, deterministic gates, and review evidence that survives beyond the session.

## Short Pitch

Install Beryl when a repository needs to be ready for AI coding agents.

It gives the repo canonical agent instructions, task routing, deterministic checks, test-change detection, generated root shims, component profiles, and human-owned review boundaries.

## One-Liners

- Hard guarantees for agent-ready repositories.
- Install the repository contract agents must follow.
- Make agent work reviewable after the chat window closes.
- Skills make agents smarter. Beryl makes repositories ready.
- Deterministic gates around stochastic contributors.

## Audience Messages

For maintainers:
Beryl keeps agent contributions inside visible repository rules, checks, and review boundaries.

For teams:
Beryl gives every agent the same local contract and makes check evidence easier to inspect.

For builders:
Beryl turns a prompt-heavy workflow into installable project infrastructure.

For students and researchers:
Beryl makes agentic development easier to study because instructions, checks, and decisions live in versioned files.

## Differentiation

Skill packs and runtime harnesses improve how an agent behaves during a session. Beryl prepares the repository around that session.

The difference matters because repository state outlives the model call. A reviewer can inspect Beryl's instruction shims, component manifest, testing policy, affected-test gate, test manifest, and driver state. They do not have to reconstruct the engineering process from memory or a chat transcript.

## Proof Points

- `.beryl/agent/` is the canonical source of truth for agent instructions, architecture notes, testing policy, security policy, and task routing.
- `.beryl/agent/scripts/sync-agent-env.sh` generates root instruction shims for tools that require fixed file locations.
- `.beryl/scripts/check.sh` is the aggregate deterministic gate.
- `.beryl/scripts/check-tests-unchanged.sh` detects unreviewed changes to the configured test scope.
- `.beryl/scripts/check-affected.sh` maps changed files to related tests or full-test fallback commands.
- `.beryl/beryl.components.json` declares installable components, profiles, dependencies, root paths, and post-install hooks.
- `.beryl/driver/` runs long tasks through separate plan, implement, verify, and commit phases with file-backed state.

## Copy Guardrails

Say:

- "Hard, inspectable process guarantees."
- "Repository-ready for agents."
- "Review evidence, not trust in a transcript."
- "Runtime-agnostic control plane."

Do not say:

- "Beryl guarantees correct code."
- "Beryl makes agents safe."
- "Beryl replaces review."
- "Beryl is a better skill pack."
