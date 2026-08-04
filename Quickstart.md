# Quickstart

<p align="center">
  <img src="./assets/beryl-logo.svg" alt="Beryl logo" width="180" />
</p>

Beryl adds repository-owned agent instructions, setup files, and deterministic
checks. Use this page to get to the path you need quickly.

## Pick Your Path

- [I want my coding agent to set up Beryl](#agent-sets-up-beryl)
- [I want to install Beryl myself](#install-beryl-yourself)
- [Beryl is already installed](#beryl-is-already-installed)
- [I want to run my first agent task](#run-your-first-agent-task)
- [I want the driver workflow](#use-driver-workflows)
- [Something failed](#when-something-fails)

## Agent Sets Up Beryl

Open your target repository in the coding agent. Do not clone Beryl first. Send:

```text
Set up Beryl for this repository.

First fetch and read this Beryl setup skill:
https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/.beryl/agent/skills/using-beryl/SKILL.md

Follow it exactly. Install Beryl into the current repository without cloning
Beryl. Preserve existing code, tests, docs, and agent instruction files. Move
durable agent guidance into .beryl/agent/ and ask before replacing any existing
root instruction file with a Beryl-generated shim. Run the prescribed checks and
report changed files, preserved files, conflicts, and results.
```

For repeatable setup, replace `main` with a trusted tag or commit SHA.

## Install Beryl Yourself

Linux/macOS:

```bash
BERYL_REF=main
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh -o beryl-install.sh
sh beryl-install.sh --ref "$BERYL_REF" --interactive
```

Windows: download in PowerShell, then run from Git Bash or WSL:

```powershell
$env:BERYL_REF = "main"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh" `
  -OutFile "beryl-install.sh"
bash -lc 'sh beryl-install.sh --ref "$BERYL_REF" --interactive'
```

For repeatable installs, replace `main` with a trusted tag or commit SHA before
running the command.

## Beryl Is Already Installed

Run the main check from the repository root:

```bash
./.beryl/scripts/check.sh
```

Optional local pre-commit guard:

```bash
git config core.hooksPath .beryl/githooks
```

Only run the hook command inside a Git repository where `.git/config` is
writable.

## Run Your First Agent Task

Start with a plan. Send your agent a short request like:

```text
Feature:
Update the first-run onboarding docs.

Expected behavior:
- Make the setup path clearer for new users.
- Keep changes limited to documentation.
- Run the configured Beryl checks.

Use .beryl/agent/task-routing.md and the planning workflow.
Present the plan for my approval. Do not implement yet.
```

After approval, send the implementation prompt:

```text
Implement the approved feature plan.
```

Review the diff and the reported check output before merging.

## Use Driver Workflows

Install with the full profile when you want `.beryl/driver/run.sh` and
driver-managed tasks:

```bash
./.beryl/scripts/setup-project.sh --profile full /path/to/project
```

If Beryl is already installed without the driver component, rerun setup with
`--profile full` or `--components driver`.

## When Something Fails

- Check output is authoritative. Fix the reported failure and rerun
  `./.beryl/scripts/check.sh`.
- If bootstrap fails, inspect `.beryl/agent/bootstrap-status.json`.
- If hook setup fails, confirm you are inside a Git repo and `.git/config` is
  writable.
- Do not weaken tests to make setup or implementation pass.

## Common Commands

| Need | Command or File |
| --- | --- |
| Install into another repo from a local checkout | `./.beryl/scripts/setup-project.sh /path/to/project` |
| Install full driver workflow | `./.beryl/scripts/setup-project.sh --profile full /path/to/project` |
| Bootstrap repo-specific context | `./.beryl/scripts/setup-project.sh --bootstrap /path/to/project` |
| Run deterministic checks | `./.beryl/scripts/check.sh` |
| Enable local pre-commit checks | `git config core.hooksPath .beryl/githooks` |
| Route an agent task | `.beryl/agent/task-routing.md` |
| Check testing rules | `.beryl/agent/testing-policy.md` |
| Check repo operating rules | `.beryl/agent/agent-rules.md` |

## Where to go deeper

- [README.md](./README.md): setup choices and project overview
- [Cheatsheet.md](./Cheatsheet.md): command and workflow reference
- [.beryl/scripts/README.md](./.beryl/scripts/README.md): install flags and troubleshooting
- [.beryl/agent/task-routing.md](./.beryl/agent/task-routing.md): workflow selection
- [.beryl/agent/skills/planning/SKILL.md](./.beryl/agent/skills/planning/SKILL.md): planning workflow
- [.beryl/agent/skills/adding-features/SKILL.md](./.beryl/agent/skills/adding-features/SKILL.md): feature workflow
