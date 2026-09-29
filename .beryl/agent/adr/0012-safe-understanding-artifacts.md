# ADR 0012: Render understanding artifacts from structured passive data

## Status

Accepted — 2026-09-29

## Context

Codebase explanations sometimes need an interactive local artifact, but source
files, issues, diffs, fixtures, and tool output are untrusted input. Rendering
that material as live HTML or allowing it to control scripts would turn a
read-only teaching workflow into an execution surface.

## Decision

`understand-codebase` is the canonical teaching workflow. It may generate a
self-contained HTML artifact only through its tracked renderer and structured
content data. The renderer escapes all derived text, embeds no network
dependencies, and uses fixed local controls. Artifacts live under ignored
`.beryl/artifacts/understanding/<timestamp>-<slug>/` and are removed after use
unless a user explicitly asks to retain them. `explaining-codebase` is only a
compatibility alias.

## Consequences

The artifact remains reviewable and safe to open locally, at the cost of a
small renderer and fixture test. The workflow can explain safe test/trace
evidence but must not execute arbitrary repository code to produce a visual.
