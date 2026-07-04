# ADR 0005: Git-History-Free Modular Installer

## Status

Accepted.

## Context

Users need to install Beryl into existing projects without cloning Beryl history and without accepting every optional component. The installer must be inspectable and usable from a raw GitHub URL.

## Decision

Use `.beryl/beryl.components.json` as the component/profile source of truth and expose `install.sh` as the one-line entry point.

The installer:

- accepts `--profile` and `--components`;
- resolves component dependencies from the manifest;
- installs only selected manifest paths;
- applies an explicit root conflict policy;
- runs declared post-install hooks;
- writes `.beryl/lock.json` last.

`.beryl/scripts/setup-project.sh` consumes the same manifest for local onboarding.

## Consequences

Component behavior is defined once. The manifest parser is intentionally constrained so the installer can stay shell-based; if the manifest schema grows, the parser requirement should be revisited before adding more JSON complexity.
