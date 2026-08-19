# Security Policy

## Access Defaults

1. Read-only access by default for tools and integrations.
2. Human approval required for destructive operations, production writes, migrations, and dependency upgrades.

## Secret Handling

- Never place secrets in prompts, markdown instructions, source code, tests, or logs.
- Use `.env.example` for non-secret shape only.
- Store real credentials in a secret manager or secure local environment.
- Deterministic enforcement: `.beryl/scripts/check-secrets.sh` runs inside
  `./.beryl/scripts/check.sh` (worktree scan in CI, staged scan at
  pre-commit), so detection does not depend on agent behavior. Annotate
  documented fake values with `beryl:allow-secret` on the same line.
- Set `BERYL_SECRET_SCANNER=gitleaks` to additionally run gitleaks where it
  is installed.

## Tooling Rules

- Prefer deterministic local checks over remote mutable operations.
- Scope filesystem and external tool access to the repository workspace.
- Use separate credentials for agent tooling where external access is required.

## Current Security Features

- `install.sh` enforces HTTPS-only remote fetches, canonical owner-slug references,
  manifest path constraints, and archive digest checks. Every remote lifecycle
  command requires a full 40-character commit SHA and matching trusted archive
  SHA-256; the lock persists it as `expectedSourceSha256` for locked update
  reuse and a missing/mismatched digest is a refusal. Published commands use
  HTTPS-only redirects and TLS protections, and never pipe a remote installer
  to a shell.
- `validate-components.sh` checks manifest integrity and enforces allowed root-path
  targets.
- `run.sh` and project scripts use strict argument tokenization for external command
  invocations.
- `beryl-bootstrap.sh` is Beryl's signed-release selector. Its embedded public key verifies detached metadata before parsing, requires valid expiry and immutable SHA/digest fields, derives rather than trusts the codeload URL, verifies the archive, and executes only its verified `install.sh`. The matching private key is an offline/protected maintainer credential, never a repository or CI secret.
- `.beryl/scripts/check-install-surface.sh` verifies dry-run copy scope against the
  selected component graph, preventing silent broadening of copied artifacts.
- Bootstrap command templates are validated for required placeholders before execution.

## Target Lifecycle Filesystem Boundary

ADR 0010 defines the filesystem contract for initial install, locked update,
restore, conservative uninstall, and explicit adoption.

- The lifecycle engine validates the target lexically and inspects every
  existing ancestor and planned destination leaf without following symbolic
  links before `mkdir`, `cd`, or other target mutation.
- It builds one mutation ledger before applying changes. The ledger includes
  managed files and modes, root contracts, `.gitignore`, `.beryl/lock.json`,
  and Git configuration so a failed lifecycle phase can restore all of them.
- The managed ledger records lifecycle state and rollback boundaries; it does
  not authorize deletion. Normal updates preserve deselected ambiguous paths
  and remove them from Beryl ownership. Explicit profile/component selection is
  required for uninstall and restore cleanup authorization.
- It treats a pre-existing `.beryl` without a valid ownership ledger as unowned
  and refuses it by default. Explicit adoption accepts only an identical staged
  managed surface; it never silently adopts unknown or target-owned content.
- It writes the lockfile only after lifecycle changes and installed-readiness
  verification succeed: a candidate lock is verified before atomic commit and
  the committed lock is verified again. A lockfile cannot claim success for a
  partial operation.
- Restore requires explicit historical `--profile`/`--components`, plus `--current-profile` or
  `--current-components` before removing current-only paths. It validates
  remote ref/digest before fetch and current source before removal. Uninstall
  requires explicit `--profile`/`--components`, removes only selected unchanged
  digest-proven paths, and both restore recorded hook configuration only when
  Beryl owns it.
- No-argument adoption infers only minimal, standard, or full from distinctive
  installed files, then requires byte-identical staged content. It refuses
  partial or ambiguous surfaces instead of widening ownership.
- External coding-agent bootstrap is an explicit standalone post-transaction
  action. Its mutations are outside the rollback guarantee and its failure is
  reported separately.

## Planned Hardening Targets

- Signed component manifest validation and distribution-key trust checks.
- Bootstrap change diff policy in a repository-owned allowlist.
- Controlled allowlist for third-party binaries invoked by automation wrappers.
- Prompt policy enforcement for bootstrap fallback paths that currently route through
  shell commands.
