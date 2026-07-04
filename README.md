<p align="center">
  <img src="assets/beryl-logo.svg" alt="Beryl faceted emerald logo mark" width="220" />
</p>

<h1 align="center">Beryl</h1>

<p align="center">
  <strong>Make Repositories Ready For Agents</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/repository-agent--ready-0f766e?style=for-the-badge" alt="Agent-ready repository" />
  <img src="https://img.shields.io/badge/guarantees-deterministic-2563eb?style=for-the-badge" alt="Deterministic guarantees" />
  <img src="https://img.shields.io/badge/review-human%20owned-111827?style=for-the-badge" alt="Human owned review" />
  <img src="https://img.shields.io/badge/control-plane-installable-b45309?style=for-the-badge" alt="Installable control plane" />
</p>

Beryl is a hard guarantee layer for AI-assisted software development. It installs into a repository and turns vague agent behavior into an explicit operating contract: what context must be read, which workflows are allowed, what checks must run, which files are generated, and where human review remains responsible.

Use it when you want a repository to be ready for agents before the agents arrive.

Skill packs and runtime harnesses teach an agent how to behave during a session. Beryl prepares the repository around that session: canonical instructions, root shims, deterministic gates, lockable install profiles, test-change detection, affected-test routing, and review artifacts that survive after the chat window is gone.

## Why Beryl Exists

AI coding agents are useful because they can inspect a codebase, form a plan, use tools, recover from failures, and adapt to local context. They are risky because their behavior is shaped at runtime by prompts, files, tools, state, and assumptions.

Beryl treats the repository itself as the engineering surface.

Instead of asking a model to "just code", Beryl makes the repository declare the contract:

- what context the agent must read before changing files
- how the task is routed before implementation starts
- which boundaries, terms, and security rules are canonical
- how success checks and commit boundaries are stated before coding
- how test changes, generated shims, and project checks stay visible
- where automation stops and human review owns the final decision

Here is the simple goal Beryl tries to achieve:

> Convert a normal repository into an agent-ready repository with inspectable guarantees.

## What You Get

```mermaid
flowchart LR
    A[Repository] --> B[Installable control plane]
    B --> C[Canonical agent contract]
    C --> D[Deterministic gates]
    D --> E[Reviewable agent work]
    E --> F[Human-owned decision]
```

Key pieces:

- `.beryl/agent/`: canonical instructions, architecture notes, testing policy, security policy, task routing, and reusable agent context.
- `.beryl/agent/skills/`: workflow contracts for planning, feature work, debugging, codebase explanation, architecture improvement, entropy tracking, and vertical-slice testing.
- `.beryl/scripts/`: deterministic checks, test manifest tooling, affected-test routing, and project setup.
- `.beryl/githooks/`: optional local pre-commit guardrails.
- `.beryl/driver/`: prompt driver utilities for repeatable plan, implement, verify, and commit flows.

## The Hard Guarantees

Beryl cannot guarantee that a model is always correct. It can guarantee that the repository exposes the controls needed to catch, route, and review agent work.

| Guarantee | Backing mechanism |
| --- | --- |
| Agents get the same local contract across supported tools. | Generated root shims from `.beryl/agent/tool-instruction-template.md` into `AGENTS.md`, `CLAUDE.md`, Cursor, Copilot, and Codex paths. |
| Agent behavior starts from repository-owned context, not hidden chat memory. | `.beryl/agent/` canonical files for architecture, testing policy, task routing, security policy, and vocabulary. |
| Workflows are selected before implementation. | `.beryl/agent/task-routing.md` plus workflow-specific `SKILL.md` contracts. |
| Feature work has an approval gate. | The `adding-features` workflow requires a ratified plan before implementation. |
| Checks have one deterministic entry point. | `./.beryl/scripts/check.sh` runs markdown checks, component manifest validation, test-manifest detection, and project checks. |
| Test changes are visible. | `./.beryl/scripts/check-tests-unchanged.sh` compares the configured test scope against `tests/.manifest.sha256`. |
| Project checks can scale from small changes to broad changes. | `./.beryl/scripts/check-affected.sh` routes staged, worktree, or base-ref changes to related tests or a full-test fallback. |
| Installed capabilities are explicit. | `.beryl/beryl.components.json` defines components, profiles, dependencies, root paths, and post-install hooks. |
| Long-running agent work can be bounded. | `.beryl/driver/` runs plan, implement, verify, and commit phases as separate headless sessions with file-backed state. |

These are process guarantees, not magic. Beryl makes the repo auditable so agent output can be trusted only after it passes the same visible gates a human reviewer can inspect.

## How Beryl Is Different

Beryl is adjacent to projects like Superpowers and other agent skill/runtime frameworks, but it is aimed at a different layer.

| Layer | Skill packs and runtime harnesses | Beryl |
| --- | --- | --- |
| Primary job | Improve how an agent behaves inside a session. | Prepare the repository so any agent session has durable rules, gates, and review evidence. |
| Unit of installation | Agent runtime, CLI, IDE, or harness profile. | Repository control plane under `.beryl/` plus generated root contracts. |
| Source of truth | Runtime-loaded skills, prompts, or harness bootstrap. | Versioned repository files, component manifest, lockfile, test manifest, and scripts. |
| Main risk addressed | The agent forgets or skips a useful behavior pattern. | The repository cannot prove what the agent was supposed to do or which checks guarded it. |
| Strength | Better in-session agent capability. | Harder-to-miss repository guarantees around context, checks, boundaries, and review. |
| Best together | Use skills to make the agent smarter. | Use Beryl to make the repository ready to receive that agent safely. |

Beryl should be boring in the places that matter: one install path, one canonical instruction source, one deterministic check entry point, visible test-change detection, and explicit human review boundaries.

## Make A Repository Agent-Ready

An agent-ready repository has four properties:

1. The agent knows where the local truth lives.
2. The agent must choose a workflow before touching implementation.
3. The repository can run deterministic checks without relying on the agent's claims.
4. Reviewers can see the contract, the checks, and the changed artifacts after the session ends.

Beryl installs those properties as files and scripts, not as advice hidden in a prompt.

### Brand Toolkit

Primary and variant marks live under `assets/`:

- Full logo: `assets/beryl-logo.svg`
- Square mark: `assets/beryl-logo-square.svg`
- Monochrome mark: `assets/beryl-logo-monochrome.svg`
- Inverted mark: `assets/beryl-logo-inverted.svg`
- Favicon mark: `assets/favicon.svg`
- Social preview: `assets/beryl-social-preview.svg`
- Brand guide: `assets/brand/beryl-brand-guide.md`

## Who It Is For

Beryl is useful for:

- engineers making real repositories safe enough for agent-assisted development
- teams that want agent output to stay legible, bounded, and reviewable across tools
- students and builders turning AI coding workflows into serious proof-of-work
- maintainers who want deterministic gates around stochastic contributors

It is not a replacement for code review, tests, architecture judgment, or product taste. It is the repository layer that makes those things harder for an agent to bypass.

## Quick Start

Install Beryl into an existing repository without cloning this repo:

```bash
curl -fsSL https://raw.githubusercontent.com/praneeth/Beryl/main/install.sh | sh
```

Select a profile or explicit components:

```bash
curl -fsSL https://raw.githubusercontent.com/praneeth/Beryl/main/install.sh | sh -s -- --profile minimal
curl -fsSL https://raw.githubusercontent.com/praneeth/Beryl/main/install.sh | sh -s -- --components agent-core,driver
```

Inspect before running:

```bash
curl -fsSL https://raw.githubusercontent.com/praneeth/Beryl/main/install.sh -o install.sh
sha256sum install.sh
less install.sh
sh install.sh --profile standard
```

The current local `install.sh` checksum is:

```text
a2275c5947a9dbf4a6997f1a24d9a6da044b549239e1684c4fc822f7ad185cf5  install.sh
```

Run the deterministic checks:

```bash
./.beryl/scripts/check.sh
```

Install the control plane into another project:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

The setup script copies the agent control plane, configures affected-test behavior, syncs generated instruction shims, creates the initial test manifest, and can enable the bundled pre-commit hook.

Enable the local hook in this repository:

```bash
git config core.hooksPath .beryl/githooks
```

## Operating Model

Beryl keeps the model flexible while making the repository contract explicit.

| Layer                | Purpose                                                              |
| -------------------- | -------------------------------------------------------------------- |
| Human intent         | Defines the actual goal and acceptable outcome.                      |
| Agent routing        | Chooses the right workflow before changing files.                    |
| Repository rules     | Gives the agent local language, architecture, and safety boundaries. |
| Deterministic checks | Turns review from vibes into repeatable evidence.                    |
| Human review         | Keeps responsibility with the engineer, not the model.               |

## Repository Status

Beryl is a repository control plane for disciplined agentic engineering. Its strongest claim is not that agents become perfect; it is that the repository gets hard, inspectable guarantees before agent work begins.

Interested in this area? Email me at praneeth.suresh.s@gmail.com.
