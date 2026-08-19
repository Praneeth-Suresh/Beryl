# Using Beryl

## Purpose

Set up Beryl in a target repository, then use its repository-owned workflow and
deterministic checks for subsequent work.

## Remote Skill Entry Point

Use this skill from the target repository. Do not require the user to clone
Beryl first.

Skill URL shape (substitute the user-approved immutable ref):

```text
https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/<trusted-ref>/.beryl/agent/skills/using-beryl/SKILL.md
```

Obtain Beryl's versioned `beryl-bootstrap.sh` through the approved,
independently trusted bootstrap channel and run `--release latest`. It verifies
signed metadata and the selected archive before executing the release
installer. Record the reported release tag, full SHA, signing key ID, and
archive digest. The pinned SHA-and-digest flow remains a recovery fallback.

For the explicit pinned recovery fallback, obtain the SHA/digest pair from the
[GitHub Releases checksum asset](https://github.com/Praneeth-Suresh/Beryl/releases).

## Setup

1. Confirm the current working directory is the target repository. Never clone
   Beryl into or beside the target unless the user explicitly asks for a local
   Beryl checkout workflow.
2. Inventory existing repository state before install:
   - application code, tests, package/build files, and docs
   - existing `.beryl/`
   - existing agent instruction files such as `AGENTS.md`, `CLAUDE.md`,
     `.codex/AGENTS.md`, `.cursor/rules/agent-rules.md`,
     `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, and
     similar tool-specific files
   - existing workflow files under `.github/workflows/`
3. Install Beryl. Prefer the approved versioned bootstrap for automatic release
   selection. If the user has provided `beryl-bootstrap.sh` or you can download
   it from the [GitHub Releases page](https://github.com/Praneeth-Suresh/Beryl/releases),
   use it directly:

   ```bash
   sh beryl-bootstrap.sh --release latest --interactive --root-conflict skip
   ```

   The bootstrap validates signed metadata and the archive, then runs the
   verified selected installer. Do not accept a raw `latest` URL alone as its
   trust root. If the bootstrap is unavailable, ask the user to provide it or
   fall back to the pinned manual procedure below.

   **Pinned manual fallback** (when a bootstrap is unavailable or audit policy
   requires an explicit SHA/digest pair):

   ```bash
   BERYL_REF='0123456789abcdef0123456789abcdef01234567' # full 40-character SHA
   BERYL_ARCHIVE_SHA256='digest-from-trusted-release-channel'
   curl --fail --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
     "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/$BERYL_REF/install.sh" \
     -o beryl-install.sh
   less beryl-install.sh
   sh beryl-install.sh --ref "$BERYL_REF" \
     --expected-sha256 "$BERYL_ARCHIVE_SHA256" \
     --interactive --root-conflict skip
   ```

   On Windows, use PowerShell only to download the file, with a ref-variable
   URL and redirects disabled, then run it from Git Bash or WSL:

   ```powershell
   $env:BERYL_REF = "0123456789abcdef0123456789abcdef01234567"
   $env:BERYL_ARCHIVE_SHA256 = "digest-from-trusted-release-channel"
   Invoke-WebRequest `
     -Uri "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/$env:BERYL_REF/install.sh" `
     -MaximumRedirection 0 `
     -OutFile "beryl-install.sh"
   ```

   Use `--bootstrap-agent` only after a successful locked lifecycle operation,
   when the user wants a supported coding agent to fill project-specific Beryl
   context. It is a standalone action and external-agent edits are outside the
   file transaction.
4. Consolidate existing agent guidance into Beryl:
   - Treat `.beryl/agent/` as the canonical home for durable agent rules,
     project brief, architecture, testing policy, vocabulary, and workflow
     routing.
   - Move or summarize durable guidance from pre-existing agent files into the
     smallest matching `.beryl/agent/` canonical file. Preserve project-specific
     meaning; do not paste stale or tool-specific boilerplate wholesale.
   - Keep application code, tests, docs, package files, and unrelated workflows
     outside Beryl.
   - Do not delete or overwrite existing non-Beryl files without explicit user
     approval. If a root agent file conflicts, preserve its content first, then
     ask before replacing it with a generated Beryl shim.
5. Regenerate Beryl-managed agent shims after consolidation:

   ```bash
   BERYL_SHIM_CONFLICT=skip ./.beryl/agent/scripts/sync-agent-env.sh
   ```

   If existing root instruction files intentionally need replacement, get
   explicit user approval first, then rerun:

   ```bash
   BERYL_SHIM_CONFLICT=overwrite ./.beryl/agent/scripts/sync-agent-env.sh
   ```
6. Configure tests only from discovered project commands. Do not invent host
   project test commands or configuration.
7. Run checks from the target repository:

   ```bash
   ./.beryl/scripts/check.sh
   ```

   Report missing prerequisites or unavailable checks instead of claiming that
   the target is verified.

## Updating Beryl

Use the downloaded `install.sh` to update an existing target only after
confirming that `TARGET/.beryl/lock.json` exists. The default update retains
the lockfile's immutable `sourceRef` and `requestedComponents`; pass `--ref`,
`--profile`, or `--components` only when the user explicitly wants to replace
that selection.

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='digest-from-trusted-release-channel'
sh beryl-install.sh --ref "$BERYL_REF" --expected-sha256 "$BERYL_ARCHIVE_SHA256" \
  --update --target /path/to/target
```

For a remote update, require a full 40-character commit SHA and matching
`--expected-sha256` from a trusted release channel whenever the source is
replaced. With neither option, the lockfile reuses `sourceRef` and
`expectedSourceSha256`; reject a missing or mismatched reused digest rather
than proceeding.

The updater stages and validates the selected release, then updates only its
file-level managed surface. Its managed ledger is state, not deletion authority:
normal updates preserve deselected or ambiguous files and remove them from
Beryl ownership. It preserves target-owned canonical agent context, custom
configuration, driver tasks and state, and user-added files. A
successful update retains replaced files under `.beryl/.updates/<timestamp>/`.
If it fails, report the structured phase/component/path/reason/rollback output
and do not claim the update succeeded.

Normal updates preserve deselected or ambiguous paths and remove them from
Beryl ownership. The managed ledger records lifecycle state; it is never
cleanup authorization.

## Setup, Recovery, And Conflicts

Use a local Beryl checkout only through `--source-dir`; it must be a Git
checkout because the lifecycle engine stages tracked release files only.
`.beryl/scripts/setup-project.sh` is a local frontend that delegates one
transaction. It supports interactive setup and `--non-interactive` with a
target directory and deterministic defaults. Pass `--root-conflict
fail|skip|overwrite` for root contracts. Hook activation is opt-in with
`--enable-githooks`; if Git already has a hooks path, require the user's choice
of `--hook-conflict fail|preserve|replace`.

Report retained update backup ids. Restore requires explicit historical
`--profile` or `--components`, and may require a Git checkout proving the
currently installed release through `--current-source-dir`. Before it removes
current-only paths, require explicit `--current-profile` or
`--current-components`. A remote restore validates the backed-up full SHA and
matching trusted archive digest before fetch:

```bash
BERYL_REF='0123456789abcdef0123456789abcdef01234567'
BERYL_ARCHIVE_SHA256='digest-from-trusted-release-channel'
sh beryl-install.sh --restore <backup-id> --ref "$BERYL_REF" \
  --expected-sha256 "$BERYL_ARCHIVE_SHA256" --target /path/to/target \
  --profile standard --current-profile full \
  --current-source-dir /path/to/current-beryl-git-checkout
```

`--uninstall` requires explicit `--profile` or `--components`, then removes
only unchanged, digest-proven selected managed paths and restores Beryl-owned
hook configuration. With no profile/components, `--adopt-existing`
infers only minimal, standard, or full from distinctive installed files; it
refuses ambiguous or partial surfaces. It records only an identical unlocked
surface from a Beryl Git checkout and never removes unknown content.

## Working With Beryl

1. Read `.beryl/agent/task-routing.md` and load the one matching workflow
   skill before editing.
2. For feature work, present a plan and wait for approval before implementing.
3. Follow the target repository's canonical agent rules and testing policy.
4. Run the narrow relevant check, then `./.beryl/scripts/check.sh`, and report
   the changed files and results for review.

For Beryl's source checkout, use `./.beryl/scripts/check.sh --development`.
Installed repositories use the default command, which checks lock-aware
readiness. Report either `ready` or `ready-with-preserved-external-contracts`.
The latter names warnings and states `Beryl does not enforce` the preserved
root/hook contract; never present it as Beryl-managed enforcement.

## References

- Remote README shape:
  `https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/<trusted-ref>/README.md`
- Remote scripts reference shape:
  `https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/<trusted-ref>/.beryl/scripts/README.md`
- Installed agent control plane: `.beryl/agent/README.md`
