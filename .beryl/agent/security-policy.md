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

