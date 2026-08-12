# Security Policy

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability.
Email praneeth.suresh.s@gmail.com with a concise description, affected Beryl
version or commit, reproduction steps, impact, and any suggested mitigation.

Reports are handled on a best-effort basis. Please allow a reasonable time for
assessment and coordination before public disclosure.

## Scope

Report vulnerabilities in this repository's installer, scripts, generated
agent-control-plane files, or published release artifacts. Security concerns
in a repository where Beryl is installed may depend on that repository's own
code and configuration; include enough detail to separate Beryl behavior from
host-project behavior.

## Supported versions

Security fixes are assessed against the current `main` branch. Releases may
state more specific support windows when they are introduced.

## Safe installation reports

When reporting an installation concern, include the full 40-character commit
SHA, the matching trusted release archive digest source, the exact lifecycle command, and
whether the operation was install, update, restore, uninstall, adoption, or
standalone bootstrap. Do not attach credentials, private repository URLs, or
agent bootstrap prompts. Beryl's published instructions download an installer
to a file over HTTPS with redirect restrictions; do not use a pipe-to-shell
command when reproducing a report.
