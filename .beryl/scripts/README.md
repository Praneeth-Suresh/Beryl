# Beryl Scripts Reference

This file is the detailed reference for install, setup, checks, component
profiles, bootstrap controls, and optional hook setup.

## Install Beryl

`install.sh` is a POSIX shell installer. The installed control-plane scripts
support the system Bash shipped with macOS and Git Bash or WSL on Windows.
Native PowerShell is supported for downloading the installer only; run it from
Git Bash or WSL after download.

Linux/macOS:

```bash
BERYL_REF=main
curl --proto '=https' --tlsv1.2 -fsSL \
  https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh -o beryl-install.sh
sh beryl-install.sh --ref "$BERYL_REF" --interactive
```

Windows PowerShell download, then Git Bash or WSL execution:

```powershell
$env:BERYL_REF = "main"
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh" `
  -OutFile "beryl-install.sh"
bash -lc 'sh beryl-install.sh --ref "$BERYL_REF" --interactive'
```

For repeatable installs, set `BERYL_REF` to a trusted tag or commit SHA instead
of `main`. The interactive command asks which component set to install,
including whether to include driver workflows, and whether a coding agent should
help fill Beryl project context.

To inspect the downloaded file before running it, use `less beryl-install.sh` as
an explicit optional review step.

Convenience one-liner, only when you accept executing remote code without local
inspection:

```bash
curl -fsSL https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/install.sh | sh
```

### Profiles And Components

Profiles are named component sets from `.beryl/beryl.components.json`:

- `minimal`: agent instructions and root tool shims.
- `standard`: minimal plus deterministic checks and githooks.
- `full`: standard plus CI and `.beryl/driver/` workflows.

Install a known profile:

```bash
BERYL_REF=main
sh beryl-install.sh --ref "$BERYL_REF" --profile minimal
sh beryl-install.sh --ref "$BERYL_REF" --profile full
```

Install explicit components and dependencies:

```bash
BERYL_REF=main
sh beryl-install.sh --ref "$BERYL_REF" --components driver
sh beryl-install.sh --ref "$BERYL_REF" --components agent-core,checks,driver
```

#### Verifying install scope

Dry-run mode prints exactly what install writes:

```bash
BERYL_REF=main
sh beryl-install.sh --source-dir . --ref "$BERYL_REF" --dry-run --profile minimal
sh beryl-install.sh --source-dir . --ref "$BERYL_REF" --dry-run --profile standard
sh beryl-install.sh --source-dir . --ref "$BERYL_REF" --dry-run --profile full
sh beryl-install.sh --source-dir . --ref "$BERYL_REF" --dry-run --components driver
```

Use `./.beryl/scripts/check-install-surface.sh` to verify those copied-path scopes
against manifest definitions in an automated check.

Use `--profile full` or `--components driver` when you need task imports,
`.beryl/driver/run.sh`, or issue-driven driver workflows. `minimal` and
`standard` do not install `.beryl/driver/`.

### Bootstrap Controls

Bootstrap asks a headless coding agent to help fill target-owned Beryl project
context after generic templates are installed.

```bash
BERYL_REF=main
sh beryl-install.sh --ref "$BERYL_REF" --bootstrap-agent --agent-runner codex
```

Custom runner example:

```bash
BERYL_REF=main
sh beryl-install.sh \
  --ref "$BERYL_REF" \
  --bootstrap-agent \
  --agent-fallback off \
  --agent-runner custom \
  --agent-command-template "/tmp/agent-runner.sh {prompt_file} {target_dir}"
```

Useful flags:

- `--profile minimal|standard|full`: install a named profile. Default:
  `standard`.
- `--components a,b`: install explicit components plus dependencies.
- `--target DIR`: install into a target directory. Default: current directory.
- `--interactive`: prompt for profile/components and agent bootstrap.
- `--bootstrap-agent`: run the optional agent context bootstrap hook.
- `--agent-fallback on|off`: continue or fail when bootstrap cannot run.
- `--agent-runner codex|claude|custom|off`: choose the bootstrap runner.
- `--agent-command-template TPL`: command template for a custom runner.
- `--expected-sha256 "$BERYL_ARCHIVE_SHA256"`: verify the downloaded archive
  against a digest you obtained from a trusted release channel.

When `--bootstrap-agent` is requested and no runner can be used, installs with
`--agent-fallback off` exit non-zero and write failure details to
`.beryl/agent/bootstrap-status.json`.

## Interactive Project Setup

For a new or existing project, run:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

If you omit the target directory, the script asks whether you are configuring an
existing project or creating a new one, then asks for the target path.

The interactive setup asks which component set to install:

- standard profile
- minimal profile
- full profile, explicitly including driver workflows
- custom comma-separated components, for example `agent-core,checks,driver`

It also asks whether a coding agent should help fill Beryl project context
before components are installed. Passing `--profile`, `--components`, or
`--bootstrap` keeps those noninteractive choices explicit.

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

The script copies the selected Beryl control-plane components, configures
`.beryl/agent/affected-tests.conf`, syncs generated instruction shims, creates
the initial test manifest, and can enable `.beryl/githooks/pre-commit`.

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

Enable it locally:

```bash
git config core.hooksPath .beryl/githooks
```

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
