<p align="center">
  <img src="assets/beryl-logo.svg" alt="Beryl logo" width="220" />
</p>

<h1 align="center">Beryl</h1>

<p align="center">
  <strong>Craft Robust Software</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/agentic%20engineering-control%20plane-0f766e?style=for-the-badge" alt="Agentic engineering control plane" />
  <img src="https://img.shields.io/badge/checks-deterministic-2563eb?style=for-the-badge" alt="Deterministic checks" />
  <img src="https://img.shields.io/badge/review-human%20owned-111827?style=for-the-badge" alt="Human owned review" />
  <img src="https://img.shields.io/badge/security-bounded%20tools-b45309?style=for-the-badge" alt="Bounded tool security" />
</p>

Beryl is an inspectable control plane for AI-assisted software development. It gives coding agents the structure they usually lack: project rules, task routing, security boundaries, deterministic checks, review expectations, and setup scripts that make their work easier to evaluate.

Use it when you want agents to help inside a real repository without turning your engineering process into an unreviewable chat transcript.

## Why Beryl Exists

AI coding agents are useful because they can inspect a codebase, form a plan, use tools, recover from failures, and adapt to local context. They are risky because their behavior is shaped at runtime by prompts, files, tools, state, and assumptions.

Beryl treats that runtime environment as an engineering surface.

Instead of asking a model to "just code", Beryl gives it a working contract:

- what context to read before changing files
- how to classify tasks before acting
- which boundaries, terms, and security rules matter
- how to state success checks before implementation
- how to keep tests and review artifacts visible
- how to leave humans responsible for final judgment

Here is the simple goal Beryl tries to achieve:

> Convert rough intent into controlled, reviewable output.

## What You Get

```mermaid
flowchart LR
    A[Human intent] --> B[Task routing]
    B --> C[Agent instructions]
    C --> D[Repository boundaries]
    D --> E[Deterministic checks]
    E --> F[Reviewable change]
    F --> G[Human decision]
```

Key pieces:

- `.beryl/agent/`: canonical instructions, architecture notes, testing policy, security policy, task routing, and reusable agent context.
- `.beryl/agent/skills/`: workflow contracts for planning, feature work, debugging, codebase explanation, architecture improvement, entropy tracking, and vertical-slice testing.
- `.beryl/scripts/`: deterministic checks, test manifest tooling, affected-test routing, and project setup.
- `.beryl/githooks/`: optional local pre-commit guardrails.
- `.beryl/driver/`: prompt driver utilities for repeatable plan, implement, verify, and commit flows.

## Who It Is For

Beryl is useful for:

- engineers experimenting with agent-assisted development in real repositories
- teams that want agent output to stay legible, bounded, and reviewable
- students and builders turning AI coding workflows into serious proof-of-work
- maintainers who want deterministic checks around stochastic contributors

It is not a replacement for code review, tests, architecture judgment, or product taste. It is the scaffolding that helps those things survive when an agent is in the loop.

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

Beryl keeps the model flexible while making the surrounding process explicit.

| Layer                | Purpose                                                              |
| -------------------- | -------------------------------------------------------------------- |
| Human intent         | Defines the actual goal and acceptable outcome.                      |
| Agent routing        | Chooses the right workflow before changing files.                    |
| Repository rules     | Gives the agent local language, architecture, and safety boundaries. |
| Deterministic checks | Turns review from vibes into repeatable evidence.                    |
| Human review         | Keeps responsibility with the engineer, not the model.               |

## Repository Status

Beryl is a framework and operating-system repository for disciplined agentic engineering. It is strongest when paired with concrete case studies that show the workflow improving a real project.

Interested in this area? Email me at praneeth.suresh.s@gmail.com.
