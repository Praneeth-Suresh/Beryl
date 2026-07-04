# ADR 0003: Use Interactive Setup Script For Project Onboarding

## Status

Accepted

## Context

Project setup now includes the agent control plane, generated instruction shims, deterministic checks, test manifest configuration, affected-test commands, and optional Git hooks. Asking each developer to wire these pieces manually increases setup errors.

Some projects will not fit the built-in framework choices. In those cases, a coding agent can complete project-specific setup from a natural-language prompt.

## Decision

Add `.beryl/scripts/setup-project.sh` as the default onboarding interface.

The script asks for a target directory, stack, test runner, hook preference, and optional AI fallback. It copies the control plane, configures `.beryl/agent/affected-tests.conf`, runs the existing shim and manifest setup scripts, and can invoke a selected headless coding agent when built-in options are insufficient.

## Consequences

- Most developers run one setup command and answer a small number of prompts.
- The deterministic shell setup remains the default path.
- AI fallback is explicit and opt-in.
- Headless agent command support may vary by local tool version, so the script supports a custom command template.
