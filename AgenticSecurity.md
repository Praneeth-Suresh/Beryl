# Agentic Security

This document records the current security feature set and immediate backlog for coding-agent workflows in this repository.

## Current Controls (Implemented)

- **No local execution of manifest payloads**: manifest parsing and validation are performed by shell utilities with schema checks and explicit path allowlists.
- **HTTPS-only remote inputs**: installer source and manifest fetch commands reject non-HTTPS URLs.
- **Canonical source identity guard**: install and component checks enforce the configured repo owner slug to prevent stale or claimable remotes.
- **Install scope validation**: every selected component must declare only repository-relative paths and allowed root files.
- **Dependency expansion**: component dependencies are resolved before copy.
- **Checksum option for immutable tarball installs**: `--expected-sha256` allows stronger integrity checks for remote archive installs.
- **Command-arg hardening for headless runners**: custom bootstrap command templates are validated for required placeholders before execution.
- **Deterministic install-surface verification**: `./.beryl/scripts/check-install-surface.sh` compares `install.sh --dry-run` output to manifest-derived expected paths.

## Near-Term Security Features (Backlog)

1. **Runner command allowlist registry**
   - Add an explicit allowlist per repository for external binaries used by bootstrap/install helpers.
   - Keep this allowlist versioned and validated in `validate-components`.

2. **Bootstrap change audit report**
   - Require `.beryl/agent/bootstrap-status.json` diff summary for each bootstrap run.
   - Fail CI when bootstrap modifies unexpected files outside `.beryl/agent/*` and allowed status artifacts.

3. **Signed installer manifest**
   - Validate manifest signatures in addition to optional SHA-256 tarball checks.
   - Keep key material in trust root outside the project write path.

4. **Structured prompt policy for agent runners**
   - Enforce tokenized prompt templates and disallow freeform shell fragments in fallback prompts.
   - Add explicit review mode for sensitive repository operations.

## Security Posture Scope

- Security automation is intentionally repository-scoped.
- The deterministic checks in `./.beryl/scripts/check.sh` must remain fast and do not replace review.
- Changes to security controls should be tracked in PR review notes and `.beryl/agent/security-policy.md`.
