# ADR 0006: Use Codebase-Driven Driver Verification

## Status

Accepted.

## Context

The driver originally assumed every task should be verified through a legacy
frontend/backend stack. That blocked documentation and control-plane tasks in
repositories that do not have that app shape, even when the repository's own
deterministic checks proved the change.

Beryl is meant to be relocatable across repositories, so verification must be
driven by the task brief and the host repo's declared checks rather than by a
hard-coded runtime layout.

## Decision

Make runtime stack startup optional and task-dependent.

The driver now exposes `VERIFY_STACK_MODE`:

- `auto` starts the bundled legacy backend/frontend verifier only when the repo
  has that layout.
- `always` keeps the previous strict behavior for projects that require it.
- `never` skips stack startup and relies on repository checks plus task-specific
  evidence.

The verify prompt now tells agents to verify against the original task brief and
`.beryl/agent/testing-policy.md`. Runtime/browser/API evidence remains required
when the task needs it, but docs, scripts, configuration, and other codebase-only
tasks can pass with source inspection and deterministic checks.

## Consequences

Driver verification now generalizes to non-web repositories and Beryl's own
control-plane tasks. Projects that need a runtime verifier must declare or
configure that requirement instead of relying on the default legacy stack.
