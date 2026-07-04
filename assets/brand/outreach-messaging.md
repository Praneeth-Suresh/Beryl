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

## Founder Story

Long-form origin narrative for launch posts, about pages, and outreach threads. The README carries a three-paragraph short version under `## Origin`; this is the expanded telling. Keep it consistent with the copy guardrails below — the story is about process discipline, never a promise of correct code.

Beryl came out of a frustration I could not engineer around: I could not stay awake all night steering my agent.

When I sat next to it, the work was good. I caught the wrong turns, corrected the assumptions, and held it to the standard I actually wanted. But that does not scale. The moment I stepped away, quality drifted. The agent would wander off the task, skip the context that mattered, invent abstractions I never asked for, or declare victory on work that did not hold up. Supervision was the only thing keeping it honest, and supervision is exactly the thing that cannot run overnight.

So I stopped trying to make the agent more trustworthy in the moment and started making the repository enforce trust on its own. If I could not be in the loop, the loop had to be built into the repo: the context it must read before touching anything, the workflow it has to choose before it implements, the deterministic checks it cannot talk its way past, and the review boundaries it is not allowed to cross. Guarantees that live in files and scripts do not fall asleep. They are there whether I am watching or not.

That shift — from babysitting the agent to hardening the repository — is the whole idea behind Beryl. The agent can run unattended and still land work I trust enough to review in the morning, because the repository already caught, routed, and gated it against a standard I set once and committed.

Beryl started as a personal project I kept reaching for, tool after tool, repo after repo. Everything I have learned about agentic engineering and context management is baked into it: how to give an agent the right context without drowning it, how to route a task before it starts, how to make checks deterministic instead of vibes, and how to keep the human as the final owner of the decision. I am putting it out in the hope it delivers the same value to others that it kept delivering to me.

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
