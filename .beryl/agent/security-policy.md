# Security Policy

## Access Defaults

1. Read-only access by default for tools and integrations.
2. Human approval required for destructive operations, production writes, migrations, and dependency upgrades.

## Secret Handling

- Never place secrets in prompts, markdown instructions, source code, tests, or logs.
- Use `.env.example` for non-secret shape only.
- Store real credentials in a secret manager or secure local environment.

## Tooling Rules

- Prefer deterministic local checks over remote mutable operations.
- Scope filesystem and external tool access to the repository workspace.
- Use separate credentials for agent tooling where external access is required.

