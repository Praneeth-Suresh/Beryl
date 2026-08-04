<p align="center">
  <img src="assets/beryl-logo.svg" alt="Beryl faceted emerald logo mark" width="220" />
</p>

<h1 align="center">Beryl</h1>

<p align="center">
  <strong>Make Repositories Ready For Agents</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/static/v1?label=repository&message=agent-ready&color=0f766e&labelColor=111827&style=flat-square" alt="Agent-ready repository" />
  <img src="https://img.shields.io/static/v1?label=checks&message=deterministic&color=2563eb&labelColor=111827&style=flat-square" alt="Deterministic checks" />
  <img src="https://img.shields.io/static/v1?label=review&message=human-owned&color=111827&labelColor=111827&style=flat-square" alt="Human-owned review" />
  <img src="https://img.shields.io/static/v1?label=control%20plane&message=installable&color=b45309&labelColor=111827&style=flat-square" alt="Installable control plane" />
</p>

<p align="center">
  <img src="assets/beryl-readme-hero.png" alt="Beryl launch slide: Hard guarantees for agent-ready repositories" width="960" />
</p>

Beryl is a hard guarantee layer for AI-assisted development. It turns the agent workflow into files, checks, and review-ready boundaries before agent output is trusted.

You get repository-owned defaults for where the contract lives, how work is routed, and which checks run. Beryl does not replace review. It makes review and recovery easier.

## Quick Start

**Recommended first read:** [Quickstart.md](./Quickstart.md) for the shortest
walkthrough from first read to first safe agent task.

### Choose A Setup Workflow

- [What You Can Do With Beryl](#what-you-can-do-with-beryl): understand the
  installed workflow before choosing commands.
- [Set Up With a Coding Agent](#set-up-with-a-coding-agent): best when you
  want the agent to install Beryl and consolidate existing agent instructions.
- [Install Directly](#install-directly): best when you want to run the
  installer yourself.
- [Use a Local Beryl Checkout](#use-a-local-beryl-checkout): best when you
  already have this repository on disk.
- [Run Checks](#run-checks): verify the installed repository.

### Set Up With A Coding Agent

Open your target repository in your coding agent. Do not clone Beryl first.
Give the agent this prompt:

```text
Set up Beryl for this repository.

First fetch and read this Beryl setup skill:
https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/.beryl/agent/skills/using-beryl/SKILL.md

Follow it exactly. Install Beryl into the current repository without cloning
Beryl. If this repo already has code, tests, docs, or agent instruction files,
preserve them, then consolidate durable agent guidance into Beryl's
.beryl/agent/ files. Ask before replacing existing root instruction files with
Beryl-managed shims. Run the prescribed checks and report changed files,
preserved files, conflicts, and results.
```

For repeatable setup, tell the agent which trusted tag or commit SHA to use
instead of `main`.

### Install Directly

Download and run the installer pinned to a ref you trust. A tag or commit SHA is
better than the moving `main`.

Linux/macOS:

```bash
BERYL_REF=main
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh -o beryl-install.sh
sh beryl-install.sh --ref "$BERYL_REF" --interactive
```

Windows: download in PowerShell, then run the installer from Git Bash or WSL
(native PowerShell execution is not supported):

```powershell
$env:BERYL_REF = "main"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh" `
  -OutFile "beryl-install.sh"
bash -lc 'sh beryl-install.sh --ref "$BERYL_REF" --interactive'
```

Convenience one-liner, only when you accept executing remote code without local
inspection:

```bash
curl -fsSL https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh | sh
```

### Use A Local Beryl Checkout

If you already have Beryl checked out locally, install it into another project:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

### Run Checks

From the installed repository:

```bash
./.beryl/scripts/check.sh
```

## What You Can Do With Beryl

Beryl gives your repo a visible agent workflow instead of relying on chat
memory or one-off prompts.

| Need | What Beryl provides |
| --- | --- |
| Add Beryl to an existing repo | Remote install, local setup, component profiles, and conflict-preserving root shims. |
| Tell agents how to work | `.beryl/agent/task-routing.md` routes each request to planning, feature work, debugging, or explanation. |
| Require plans before edits | The planning and feature skills make agents present a plan, success checks, and commit boundaries before implementation. |
| Preserve project knowledge | `.beryl/agent/` stores the project brief, architecture, testing policy, vocabulary, and durable agent rules. |
| Verify agent changes | `./.beryl/scripts/check.sh` runs Markdown, component, secret, test-manifest, and project checks. |
| Keep local guardrails | Optional githooks run the deterministic gate before commits. |
| Run larger task workflows | The full profile installs `.beryl/driver/` for driver-managed task loops. |

The normal loop is short: install Beryl, run `./.beryl/scripts/check.sh`, ask
the agent for a plan, approve the plan, let it implement, rerun checks, then
review the diff.

## Command Reference

| Script                              | What it does                                                                                                                                                                                                |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`                      | Remote install entry point. It installs selected Beryl profiles or components into the current repository.                                                                                                  |
| `.beryl/scripts/setup-project.sh` | Interactive onboarding for an existing or new project. It lets you choose the component set, including whether driver workflows are installed, and whether a coding agent should help fill project context. |
| `.beryl/scripts/check.sh`         | Deterministic safety gate for Markdown, test-manifest integrity, and configured project checks.                                                                                                             |

Detailed install flags, profiles, component examples, bootstrap controls, and
hook troubleshooting live in [.beryl/scripts/README.md](./.beryl/scripts/README.md).

## Operating Model

Beryl turns an agent request into a repo-owned loop:

| Layer | What it gives you |
| --- | --- |
| Human intent | You state the outcome, constraints, and approval points. |
| Agent routing | `.beryl/agent/task-routing.md` chooses planning, feature work, debugging, or explanation before edits begin. |
| Repository rules | `.beryl/agent/` stores the project brief, architecture, testing policy, workflow skills, and generated root shims. |
| Deterministic checks | `./.beryl/scripts/check.sh` runs the repeatable safety gate before review. |
| Human review | You approve plans, inspect diffs, and decide what merges. |

## Value Ladder

Beryl starts as a practical safety layer for one repository, then scales without changing the operating model:

<p align="center">
  <img src="assets/beryl-value-ladder.png" alt="Beryl value ladder: start with one repo, then scale to an engineering team and company fleet" width="960" />
</p>

## Origin

Beryl started as a practical answer to unattended agent runs that were hard to supervise. The repository now carries the control plane so the process is explicit, repeated, and reviewable.

Interested in this area? Email me at praneeth.suresh.s@gmail.com.
