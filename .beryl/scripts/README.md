# Beryl Scripts Reference

This file is the detailed reference for install, setup, checks, component
profiles, bootstrap controls, and optional hook setup.

## Recommended: Signed Release Bootstrap

For a remote installation, obtain a **versioned** `beryl-bootstrap.sh` through
Beryl's independently trusted bootstrap channel, inspect it, then run:

```bash
sh beryl-bootstrap.sh --release latest --interactive
```

The bootstrap embeds Beryl's release public key. It downloads fixed HTTPS
metadata assets, verifies their detached signature and expiry, derives the
codeload URL only from the signed full commit SHA, verifies the archive digest,
and executes `install.sh` extracted from that verified archive. It reports the
release tag, SHA, signing key ID, and archive SHA-256. It requires `curl`,
`tar`, `openssl`, and `sha256sum` or `shasum`; on Windows execute it from Git
Bash or WSL.

The bootstrap distribution is the initial trust boundary. A GitHub `latest`
redirect, raw URL, or release asset alone is not a trust root. Keep the pinned
`--ref` / `--expected-sha256` commands below as a manual recovery and
audit fallback. Existing locked updates remain pinned by default; automatic
selection is explicit through the bootstrap.

## Install Beryl

`install.sh` is a POSIX shell installer. The installed control-plane scripts
support the system Bash shipped with macOS and Git Bash or WSL on Windows.
Native PowerShell is supported for downloading the installer only; run it from
Git Bash or WSL after download.

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

Windows PowerShell download, then Git Bash or WSL execution:

```powershell
$env:BERYL_REF = "0123456789abcdef0123456789abcdef01234567" # full 40-character commit SHA
$env:BERYL_ARCHIVE_SHA256 = "replace-with-trusted-release-digest"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/$env:BERYL_REF/install.sh" `
  -MaximumRedirection 0 `
  -OutFile "beryl-install.sh"
bash -lc 'less beryl-install.sh && sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --interactive'
```

Remote lifecycle commands require a full 40-character commit SHA and
`BERYL_ARCHIVE_SHA256` from the trusted Beryl release channel; tags and moving
branches are refused. The command rejects non-HTTPS redirects and
uses TLS 1.2 or newer. PowerShell refuses redirects with
`-MaximumRedirection 0`; it only downloads the POSIX installer. The interactive
command asks which component set to install, including whether to include driver
workflows, and whether a coding agent should help fill Beryl project context.

The trusted channel is the matching [GitHub Release checksum asset](https://github.com/Praneeth-Suresh/Beryl/releases): download
`beryl-<full-sha>.tar.gz.sha256` from the release, use the full SHA from its
filename as `BERYL_REF`, and use its digest content as `BERYL_ARCHIVE_SHA256`.

To inspect the downloaded file before running it, use `less beryl-install.sh` as
an explicit optional review step.

Do not use pipe-to-shell installation commands. Inspect the downloaded script
before execution, and do not call a moving branch an immutable release.

### Profiles And Components

Profiles are named component sets from `.beryl/beryl.components.json`:

- `minimal`: agent instructions and root tool shims.
- `standard`: minimal plus deterministic checks and githooks.
- `full`: standard plus CI and `.beryl/driver/` workflows.

Install a known profile:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile minimal
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile full
```

Install explicit components and dependencies:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --components driver
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" --components agent-core,checks,driver
```

#### Verifying install scope

Dry-run mode prints exactly what install writes:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
sh beryl-install.sh --source-dir /path/to/beryl-git-checkout --ref "$BERYL_REF" --dry-run --profile minimal
sh beryl-install.sh --source-dir /path/to/beryl-git-checkout --ref "$BERYL_REF" --dry-run --profile standard
sh beryl-install.sh --source-dir /path/to/beryl-git-checkout --ref "$BERYL_REF" --dry-run --profile full
sh beryl-install.sh --source-dir /path/to/beryl-git-checkout --ref "$BERYL_REF" --dry-run --components driver
```

`--source-dir` is deliberately restricted to a Beryl Git checkout. The
installer uses its tracked release inventory and refuses arbitrary directories,
untracked artifacts, and source symlinks. Use
`./.beryl/scripts/check-install-surface.sh` to verify those copied-path scopes
against manifest definitions in an automated check.

Use `--profile full` or `--components driver` when you need task imports,
`.beryl/driver/run.sh`, or issue-driven driver workflows. `minimal` and
`standard` do not install `.beryl/driver/`.

### Update An Existing Installation

`--update` safely refreshes an existing installation:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh \
  --ref "$BERYL_REF" \
  --expected-sha256 "$BERYL_ARCHIVE_SHA256" \
  --update \
  --target /path/to/project
```

The target must already have `.beryl/lock.json`; updates do not bootstrap a
new installation. With no `--ref`, `--expected-sha256`, `--profile`, or
`--components`, the installer reuses the lockfile's immutable `sourceRef`,
`expectedSourceSha256`, and `requestedComponents`. Passing a source or
component option deliberately replaces that selection. A remote replacement
requires a full 40-character commit SHA and explicit matching digest; a locked
remote update reuses its recorded digest and refuses if it is absent or the
downloaded archive differs.

Before mutation, the installer stages the selected Beryl paths, validates the
manifest, builds a file-level managed-path ledger, and snapshots every path it
may mutate. The ledger is state, not destructive authority: normal updates
preserve deselected or ambiguous paths and remove them from Beryl ownership.
The manifest's `updatePreservePaths` keeps target-owned canonical agent context,
custom settings, driver configuration, tasks, state, and prior update backups
outside the update surface. A legacy lockfile without the ledger is migrated
conservatively: newly staged Beryl paths are considered managed, but no old
path is removed.

On success, replaced files are retained below
`.beryl/.updates/<timestamp>/`, and the summary reports the source ref,
components, updated and preserved counts, and backup path. On failure, the
installer restores its snapshot and emits:

```text
beryl: update failed phase=<phase> component=<component> path=<path> reason=<reason> rollback=<result>
```

The lockfile is written only after apply, post-install hooks, and
installed-readiness verification complete successfully.

Normal updates preserve deselected ambiguous paths and remove them from Beryl
ownership. The managed ledger records state and rollback boundaries; a
selection change is never cleanup authorization.

### Recovery And Ownership

List the retained backup id from a successful update summary, then restore it
transactionally. Restore refuses to remove a newer Beryl surface unless it can
prove the current installed release; supply a Git checkout of that release with
`--current-source-dir` when the backup cannot prove it itself. Restore requires
explicit historical `--profile`/`--components`, and explicit
`--current-profile`/`--current-components` before current-only paths can be
removed. Remote recovery validates the backed-up full SHA and matching trusted
archive digest before it fetches:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='replace-with-trusted-release-digest'
sh beryl-install.sh --restore <backup-id> --ref "$BERYL_REF" \
  --expected-sha256 "$BERYL_ARCHIVE_SHA256" --target /path/to/project \
  --profile standard --current-profile full \
  --current-source-dir /path/to/current-beryl-git-checkout
```

Uninstall is conservative: it requires explicit `--profile` or `--components`,
then removes only unchanged, digest-proven selected managed paths and restores
a previous `core.hooksPath` only if the lock proves Beryl owned it. It refuses
modified managed files, symlinks, unknown paths, and unselected cleanup.

```bash
sh beryl-install.sh --uninstall --ref "$BERYL_REF" \
  --expected-sha256 "$BERYL_ARCHIVE_SHA256" --profile full \
  --target /path/to/project
```

Adoption does not convert arbitrary content into Beryl ownership. With no
`--profile` or `--components`, it infers only `minimal`, `standard`, or `full`
from distinctive installed files; it refuses ambiguous or partial surfaces. It
compares the unlocked target to a tracked Beryl Git checkout, records only
identical managed files, preserves target-owned paths, and refuses conflicts:

```bash
sh beryl-install.sh --adopt-existing \
  --source-dir /path/to/beryl-git-checkout --target /path/to/project
```

### Bootstrap Controls

Bootstrap asks a headless coding agent to help fill target-owned Beryl project
context after generic templates are installed.

```bash
sh beryl-install.sh --bootstrap-agent --target /path/to/project --agent-runner codex
```

Custom runner example:

```bash
sh beryl-install.sh \
  --bootstrap-agent \
  --target /path/to/project \
  --agent-fallback off \
  --agent-runner custom \
  --agent-command-template "/tmp/agent-runner.sh {prompt_file} {target_dir}"
```

Useful flags:

- `--profile minimal|standard|full`: install a named profile. Default:
  `standard`.
- `--components a,b`: install explicit components plus dependencies.
- `--update`: refresh an existing locked installation while preserving
  target-owned paths; requires `TARGET/.beryl/lock.json`.
- `--restore BACKUP_ID`: restore one retained update backup; requires explicit
  historical `--profile` or `--components`, and may require
  `--current-source-dir` plus `--current-profile` or `--current-components`
  before current-only paths are removed.
- `--current-profile NAME` / `--current-components a,b`: explicit current
  restore authorization before removing files only present in the newer surface.
- `--uninstall`: requires explicit `--profile` or `--components`; removes only
  unchanged, digest-proven selected Beryl-managed files.
- `--adopt-existing`: record an identical unlocked Beryl surface from a Git
  checkout without replacing target content.
- `--target DIR`: install into a target directory. Default: current directory.
- `--source-dir DIR`: use a local Beryl Git checkout only; it never copies an
  arbitrary source directory.
- `--interactive`: prompt for profile/components and agent bootstrap.
- `--bootstrap-agent`: standalone post-transaction action against a locked
  target; it cannot be combined with install or update.
- `--root-conflict fail|skip|overwrite`: explicit policy for existing root
  contracts. The default is refusal and the choice is persisted in the lock.
- `--enable-githooks`: request Beryl's hook integration. With a pre-existing
  `core.hooksPath`, select `--hook-conflict fail|preserve|replace`; Beryl never
  silently takes ownership of another hook manager.
- `--agent-fallback on|off`: continue or fail when bootstrap cannot run.
- `--agent-runner codex|claude|custom|off`: choose the bootstrap runner.
- `--agent-command-template TPL`: command template for a custom runner.
- `--expected-sha256 "$BERYL_ARCHIVE_SHA256"`: verify the downloaded archive
  against a digest from a trusted release channel. Required with every remote
  lifecycle command; recorded as `expectedSourceSha256` and reused by a locked
  remote update unless an explicit replacement SHA/digest is supplied.

When `--bootstrap-agent` is requested and no runner can be used, standalone
bootstrap with `--agent-fallback off` exits non-zero and writes failure details to
`.beryl/agent/bootstrap-status.json`.

## Interactive Project Setup

For a new or existing project, run:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

Interactive setup requires a target directory and gathers profile, test-adapter,
root-contract, hook, and optional bootstrap choices before it delegates exactly
one lifecycle transaction to `install.sh`.

The interactive setup asks which component set to install:

- standard profile
- minimal profile
- full profile, explicitly including driver workflows
- custom comma-separated components, for example `agent-core,checks,driver`

It also asks whether a coding agent should help fill Beryl project context
after the lifecycle has committed. `--non-interactive` never reads stdin and
requires the target directory; unspecified new-target values are deterministic:
standard profile, generic stack, no test runner, no bootstrap, and no automatic
check. Provide `--profile` or `--components`, `--root-conflict`,
`--enable-githooks`, and `--hook-conflict` when your automation needs a
different explicit policy.

Install and immediately bootstrap repo-specific agent context files:

```bash
./.beryl/scripts/setup-project.sh --bootstrap /path/to/project
```

Install with explicit bootstrap runner controls:

```bash
./.beryl/scripts/setup-project.sh \
  --bootstrap \
  --agent-fallback off \
  --agent-runner custom \
  --agent-command-template "/tmp/agent-runner.sh {prompt_file} {target_dir}" \
  /path/to/project
```

Setup configures the selected test adapter only after the delegated transaction
commits. It does not independently copy components, write lockfiles, initialize
Git, sync shims, or alter `core.hooksPath`; linked Git worktrees are detected
through Git rather than by assuming `.git` is a directory.

When the listed stack or test-runner options are not enough, choose `Use AI
agent fallback`. The script will ask for a project/setup prompt and run Codex,
Claude, or a custom headless command from inside the target project.

## Deterministic Checks

Single entrypoint:

```bash
./.beryl/scripts/check.sh
```

`check.sh` runs:

1. `check-md.sh`
2. `check-tests-unchanged.sh`
3. `check-project.sh` (project-specific extension point)

`check-project.sh` delegates to the affected test gate:

```bash
./.beryl/scripts/check-affected.sh --worktree
```

The gate reads `.beryl/agent/affected-tests.conf`.

- Configure `RELATED_TEST_CMD` for test runners that can select tests from changed files.
- Configure `FULL_TEST_CMD` for broad changes that should run the whole project test suite.
- Leave both empty until the project has a real test runner; the gate will report that no project tests are configured and keep the deterministic checks passing.

Examples:

```bash
# Jest
RELATED_TEST_CMD=(npx --no-install jest --findRelatedTests --passWithNoTests)
FULL_TEST_CMD=(npm test)

# pytest with testmon
RELATED_TEST_CMD=(pytest --testmon)
FULL_TEST_CMD=(pytest)
```

## Test Immutability (Detection)

This repo uses a committed SHA-256 manifest over a configurable test scope.

- Scope is configured in `.beryl/agent/test-manifest.conf` via:
  - `MANIFEST_PATH`
  - `INCLUDE_GLOBS`
  - `EXCLUDE_GLOBS`
- `./.beryl/scripts/check-tests-unchanged.sh` fails if any file in the configured scope differs from the manifest.
- If a test change is intentional, update the manifest:

```bash
./.beryl/scripts/update-test-manifest.sh
```

Commit both the test changes and the updated manifest together.

This mechanism provides deterministic detection of test changes. It does not create absolute immutability against privileged repository writes.

## Run On Every Commit (Optional)

This repo includes a git hook at `.beryl/githooks/pre-commit`.

Enable it through `install.sh --enable-githooks` or setup's
`--enable-githooks`. Do not overwrite an existing hook manager manually.

The hook runs `./.beryl/scripts/check.sh` with `CHECK_AFFECTED_MODE=staged`, so project tests are selected from the files staged for that commit. Manual `./.beryl/scripts/check.sh` uses worktree mode and selects from all changes relative to `HEAD`.

Hook setup requires:

- Running inside a Git repository, or after `git init`.
- Permission to write `.git/config`.
- The `githooks` component installed, normally through the `standard` or `full`
  profile.

Common failures:

- `fatal: not a git repository`: run the command after `cd` into a repository.
- `fatal: could not lock config file ...`: `.git/config` is read-only or locked
  by filesystem permissions.

When hook setup is blocked, keep the path install complete and rerun the hook
command after fixing repository write access.
## Installed Readiness

Run `./.beryl/scripts/check.sh` from an installed target. It runs the
lock-aware doctor before the deterministic gate and reports incomplete or
ambiguous state as failure. Run `./.beryl/scripts/check.sh --development` only
from Beryl's source checkout; that mode verifies source-release-only assets as
well. The doctor reports either `ready` or
`ready-with-preserved-external-contracts`. The latter emits a named warning for
each preserved root contract or hook and says `Beryl does not enforce` that
external contract; it is not silent Beryl enforcement.

## CI Lifecycle Regression Runner

GitHub Actions runs `.beryl/scripts/run-lifecycle-tests.sh` in the
`lifecycle-regressions` job. It executes every tracked shell regression test,
including installation security, setup lifecycle, source/release trust,
recovery, hooks, readiness, and this documentation contract. Run the same
command locally before publishing a lifecycle change:

```bash
./.beryl/scripts/run-lifecycle-tests.sh
```
