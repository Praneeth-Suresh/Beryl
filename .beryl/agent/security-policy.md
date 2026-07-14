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
  manifest path constraints, and optional archive digest checks.
- `validate-components.sh` checks manifest integrity and enforces allowed root-path
  targets.
- `run.sh` and project scripts use strict argument tokenization for external command
  invocations.
- `.beryl/scripts/check-install-surface.sh` verifies dry-run copy scope against the
  selected component graph, preventing silent broadening of copied artifacts.
- Bootstrap command templates are validated for required placeholders before execution.

## Planned Hardening Targets

- Signed component manifest validation and distribution-key trust checks.
- Bootstrap change diff policy in a repository-owned allowlist.
- Controlled allowlist for third-party binaries invoked by automation wrappers.
- Prompt policy enforcement for bootstrap fallback paths that currently route through
  shell commands.
