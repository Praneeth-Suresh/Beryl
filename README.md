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

**Recommended first read:** [Quickstart.md](./Quickstart.md) — short, story-style onboarding from first read to first safe agent task.

Recommended install: download the installer, inspect it, then run it pinned to
a ref you trust (a tag or commit SHA instead of the moving `main`):

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh -o beryl-install.sh
less beryl-install.sh   # inspect before executing
sh beryl-install.sh --ref <tag-or-commit-sha>
```

To verify the downloaded archive against a published digest, add
`--expected-sha256 <hex>`; the installer refuses to install on mismatch.

Convenience one-liner (executes remote code without inspection — only use it
when you accept that trade-off):

```bash
curl -fsSL https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh | sh
```

Run the primary repo safety gate:

```bash
./.beryl/scripts/check.sh
```

Install the control plane into another project:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

Install and immediately bootstrap repo-specific agent context files:

```bash
./.beryl/scripts/setup-project.sh --bootstrap /path/to/project

# install with explicit bootstrap runner controls
./.beryl/scripts/setup-project.sh --bootstrap --agent-fallback off --agent-runner custom --agent-command-template "/tmp/agent-runner.sh {prompt_file} {target_dir}" /path/to/project
```

Install from a remote URL and bootstrap in-place:

```bash
sh beryl-install.sh --ref <tag-or-commit-sha> --bootstrap-agent --agent-runner codex
```

If you plan to use driver workflows (task imports, `driver/run.sh`, issue bootstraps), install with:

```bash
./.beryl/scripts/setup-project.sh --profile full /path/to/project
# or
./.beryl/scripts/setup-project.sh --components driver /path/to/project
```

The `standard` and `minimal` profiles do not install `.beryl/driver/`.

When bootstrap is requested and no runner can be used, install exits non-zero by default when `--agent-fallback off` is set and writes failure details to `.beryl/agent/bootstrap-status.json`.

Optional local pre-commit guardrail:

```bash
git config core.hooksPath .beryl/githooks
```

Hook setup requires:

- Running inside a Git repository (or after `git init`).
- Permission to write `.git/config`.

Common failures:

- `fatal: not a git repository` → run the command after `cd` into a repo.
- `fatal: could not lock config file ...` → the `.git/config` file is read-only or locked by permissions.

When hook setup is blocked, keep the path install complete and rerun after fixing repository write access.

Pass a profile if you know your target profile:

```bash
sh beryl-install.sh --ref <tag-or-commit-sha> --profile minimal
sh beryl-install.sh --ref <tag-or-commit-sha> --profile full
```

## Documentation Map

Use this map before opening multiple files:

- User docs and references
  - [Quickstart.md](./Quickstart.md): Fast path to your first safe task.
  - [README.md](./README.md): Entry point and decision guide.
  - [Theory.md](./Theory.md): Goals, motivations, and project reasoning.
  - [Practise.md](./Practise.md): Applied examples.
  - [Cheatsheet.md](./Cheatsheet.md): Canonical command-and-workflow reference.
  - [current.md](./current.md): Current snapshot context.
  - [gitignore-sample.md](./gitignore-sample.md): Ignore pattern template.
  - [assets/brand/beryl-brand-guide.md](./assets/brand/beryl-brand-guide.md): Brand and messaging reference.
- Agent instruction surfaces
  - [AGENTS.md](./AGENTS.md): Runtime AGENTS shim; source edits should start from `.beryl/agent/tool-instruction-template.md`.
  - [CLAUDE.md](./CLAUDE.md): Runtime Claude shim; source edits should start from `.beryl/agent/tool-instruction-template.md`.
  - [.cursor/rules/agent-rules.md](./.cursor/rules/agent-rules.md): Runtime Cursor shim; source edits should start from `.beryl/agent/agent-rules.md`.
  - [.github/copilot-instructions.md](./.github/copilot-instructions.md): Runtime Copilot shim; source edits should start from `.beryl/agent/agent-rules.md`.
  - [.codex/AGENTS.md](./.codex/AGENTS.md): Runtime Codex shim; source edits should start from `.beryl/agent/agent-rules.md`.
  - [.github/workflows/deterministic-checks.yml](./.github/workflows/deterministic-checks.yml): deterministic CI entrypoint.
- Reference, design, and operational material
  - [.beryl/agent/task-routing.md](./.beryl/agent/task-routing.md): Route each request to the correct workflow.
  - [.beryl/agent/project-brief.md](./.beryl/agent/project-brief.md): Product goal and scope.
  - [.beryl/agent/design-tree.md](./.beryl/agent/design-tree.md): Evolving and settled design notes.
  - [.beryl/agent/architecture.md](./.beryl/agent/architecture.md): Bounded-context ownership.
  - [.beryl/agent/ubiquitous-language.md](./.beryl/agent/ubiquitous-language.md): Canonical project vocabulary.
  - [.beryl/agent/testing-policy.md](./.beryl/agent/testing-policy.md): Check commands and testing expectations.
  - [.beryl/agent/agent-rules.md](./.beryl/agent/agent-rules.md): Repo-level operating defaults.
  - [.beryl/agent/skills/adding-features/SKILL.md](./.beryl/agent/skills/adding-features/SKILL.md): Approved feature implementation path.
  - [.beryl/agent/skills/planning/SKILL.md](./.beryl/agent/skills/planning/SKILL.md): Planning workflow.
  - [.beryl/agent/skills/debugging/SKILL.md](./.beryl/agent/skills/debugging/SKILL.md): Debug workflow.
  - [.beryl/driver/README.md](./.beryl/driver/README.md): Driver behavior and session flow.
  - [.beryl/agent/README.md](./.beryl/agent/README.md): Source-of-truth index for agent contexts.

## Using Beryl from scratch in another repo

```bash
# copy command used in this repo setup
./.beryl/scripts/setup-project.sh /path/to/new-project
```

Optional hook setup is available during setup or at any time with:

```bash
git config core.hooksPath .beryl/githooks
```

## Adding Features (driver flow)

When you already have a feature request, run:

```bash
./.beryl/driver/run.sh
```

This path requires the `driver` component. If `./.beryl/driver/run.sh` is missing, install with `--profile full` or `--components driver`.

The driver handles plan -> implement -> verify phases against numbered tasks.

## Operating Model

| Layer                | Purpose                                                |
| -------------------- | ------------------------------------------------------ |
| Human intent         | Defines the desired outcome                            |
| Agent routing        | Selects the right workflow before edits                |
| Repository rules     | Provides the persistent contract from`.beryl/agent/` |
| Deterministic checks | Verifies edits through`./.beryl/scripts/check.sh`    |
| Human review         | Keeps final ownership with the user                    |

## Value Ladder

Beryl starts as a practical safety layer for one repository, then scales without changing the operating model:

<p align="center">
  <img src="assets/beryl-value-ladder.png" alt="Beryl value ladder: start with one repo, then scale to an engineering team and company fleet" width="960" />
</p>

## Origin

Beryl started as a practical answer to unattended agent runs that were hard to supervise. The repository now carries the control plane so the process is explicit, repeated, and reviewable.

Interested in this area? Email me at praneeth.suresh.s@gmail.com.
