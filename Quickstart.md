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
- [I want to start a large application build](#start-a-large-application-build)
- [I want the driver workflow](#use-driver-workflows)
- [Something failed](#when-something-fails)

## Agent Sets Up Beryl

Open your target repository in the coding agent. Do not clone Beryl first. Send:

```text
Set up Beryl for this repository.

First ask me for the trusted Beryl full 40-character commit SHA and matching
archive SHA-256. Fetch and read the
matching setup skill at:
https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/<trusted-ref>/.beryl/agent/skills/using-beryl/SKILL.md

Follow it exactly. Install Beryl into the current repository without cloning
Beryl. Preserve existing code, tests, docs, and agent instruction files. Move
durable agent guidance into .beryl/agent/ and ask before replacing any existing
root instruction file with a Beryl-generated shim. Run the prescribed checks and
report changed files, preserved files, conflicts, and results.
```

Remote lifecycle commands require a full 40-character commit SHA, never a tag
or moving branch.

## Install Beryl Yourself

Linux/macOS:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567' # full 40-character commit SHA
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
curl --fail --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/${BERYL_REF}/install.sh" \
  -o beryl-install.sh
less beryl-install.sh
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --interactive
```

Windows: download in PowerShell, then run from Git Bash or WSL:

```powershell
$env:BERYL_REF = "0123456789abcdef0123456789abcdef01234567" # full 40-character commit SHA
$env:BERYL_ARCHIVE_SHA256 = "replace-with-trusted-release-digest"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/$env:BERYL_REF/install.sh" `
  -MaximumRedirection 0 `
  -OutFile "beryl-install.sh"
bash -lc 'less beryl-install.sh && sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --interactive'
```

The archive digest must come from the matching [GitHub Release checksum asset](https://github.com/Praneeth-Suresh/Beryl/releases), named
`beryl-<full-sha>.tar.gz.sha256`. Do not pipe a download directly into a shell.
Native PowerShell only downloads; execute the installer from Git Bash or WSL.

## Beryl Is Already Installed

Run the main check from the repository root:

```bash
./.beryl/scripts/check.sh
```

Enable hooks through setup or install with `--enable-githooks`. If Git already
has a `core.hooksPath`, Beryl refuses by default; inspect it and choose
`--hook-conflict preserve` or `replace` explicitly. Beryl restores the prior
hook path during rollback or uninstall only when it owns that setting.

To retrieve current Beryl features without replacing your repository-owned
context, configuration, driver data, or other user files, download the
installer for a trusted release and update the target:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" \
  --update --target /path/to/project
```

The target must already contain `.beryl/lock.json`. The update reuses the
lockfile's immutable source ref, `expectedSourceSha256`, and requested
components unless `--ref`, `--expected-sha256`, `--profile`, or `--components`
is passed explicitly. A remote replacement requires a full 40-character commit
SHA and matching trusted archive digest. A digest-protected update refuses a
missing or mismatched reused digest. Normal updates preserve deselected or
ambiguous files and remove them from the ownership ledger; the ledger alone
never authorizes deletion. A successful update reports its backup under
`.beryl/.updates/<timestamp>/`; a failed update reports its phase, component,
path, reason, and rollback result.

Normal updates preserve deselected or ambiguous files and remove them from
Beryl ownership; a selection change never authorizes cleanup. To restore a
retained backup, provide the backup id,
explicit historical `--profile`/`--components`, and, before removing current-only
paths, explicit `--current-profile`/`--current-components`:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh --restore <backup-id> --ref "$BERYL_REF" \
  --expected-sha256 "$BERYL_ARCHIVE_SHA256" --target /path/to/project \
  --profile standard --current-profile full \
  --current-source-dir /path/to/current-beryl-git-checkout
```

For remote recovery, Beryl validates the locked full SHA and trusted archive
digest before fetching the recovery surface.

`--uninstall` requires explicit `--profile` or `--components`, then removes
only unchanged, digest-proven selected Beryl files and restores Beryl-owned
hook settings. With no profile/components, `--adopt-existing`
infers only minimal, standard, or full from distinctive installed files;
ambiguous or partial surfaces are refused. Adoption records only an identical
unlocked Beryl surface; it never deletes unknown content.

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

## Start a Large Application Build

After Beryl is installed, give the agent an explicit request such as:

```text
I want to build a large application for [users and outcome].

Use the initial-build workflow. Discover this repository first, then ask me
clarifying questions one at a time. Propose a hierarchical dependency plan and
wait for my ratification before editing code.
```

The agent creates the Git-tracked `.beryl/agent/hierarchy.md` only after you
ratify the plan. It implements dependency-ready nodes, records checks and
progress there, and promotes durable decisions into the canonical agent files.
The hierarchy is deleted only after every node and required check passes; an
existing hierarchy causes the next session to resume the active build.

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
- Bootstrap is standalone: after install/update, run
  `sh beryl-install.sh --bootstrap-agent --target /path/to/project`. Its
  external-agent changes are not transactional; inspect
  `.beryl/agent/bootstrap-status.json` if it fails.
- If hook setup is refused, inspect the existing `core.hooksPath` and choose a
  documented `--hook-conflict` policy rather than overwriting it manually.
- Do not weaken tests to make setup or implementation pass.

## Common Commands

| Need | Command or File |
| --- | --- |
| Install from a local Beryl Git checkout | `./.beryl/scripts/setup-project.sh /path/to/project` |
| Noninteractive local setup | `./.beryl/scripts/setup-project.sh --non-interactive --profile standard /path/to/project` |
| Install full driver workflow | `./.beryl/scripts/setup-project.sh --profile full /path/to/project` |
| Update an existing installation | `sh beryl-install.sh --update --target /path/to/project` |
| Bootstrap repo-specific context | `sh beryl-install.sh --bootstrap-agent --target /path/to/project` |
| Run deterministic checks | `./.beryl/scripts/check.sh` |
| Restore an update backup | `sh beryl-install.sh --restore <backup-id> --profile standard --current-profile full --target /path/to/project` |
| Conservative uninstall | `sh beryl-install.sh --uninstall --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile full --target /path/to/project` |
| Route an agent task | `.beryl/agent/task-routing.md` |
| Check testing rules | `.beryl/agent/testing-policy.md` |
| Check repo operating rules | `.beryl/agent/agent-rules.md` |
| Plan a large or greenfield build | `.beryl/agent/skills/initial-build/SKILL.md` |

## Where to go deeper

- [README.md](./README.md): setup choices and project overview
- [Cheatsheet.md](./Cheatsheet.md): command and workflow reference
- [.beryl/scripts/README.md](./.beryl/scripts/README.md): install flags and troubleshooting
- [.beryl/agent/task-routing.md](./.beryl/agent/task-routing.md): workflow selection
- [.beryl/agent/skills/planning/SKILL.md](./.beryl/agent/skills/planning/SKILL.md): planning workflow
- [.beryl/agent/skills/adding-features/SKILL.md](./.beryl/agent/skills/adding-features/SKILL.md): feature workflow
## Readiness States

An installed target runs `./.beryl/scripts/check.sh`; it uses the lockfile and
installed readiness contract. Beryl's source checkout alone uses
`./.beryl/scripts/check.sh --development`, which additionally validates
source-release surfaces. A successful doctor reports either `ready` or
`ready-with-preserved-external-contracts`. The latter names each preserved root
contract or hook warning and states that Beryl does not enforce it; incomplete
or ambiguous installations do not report green.
