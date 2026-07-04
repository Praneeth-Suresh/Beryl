# Project Brief

## Product Goal

Build **Beryl** for **engineers, maintainers, and teams adopting AI coding agents** so they can **make repositories ready for agents with inspectable instructions, deterministic gates, and human-owned review boundaries**.

## Primary Workflows

1. **Install control plane**: add `.beryl/` components, generated root shims, and lockfile-backed setup to an existing repository.
2. **Route agent work**: classify requests into planning, feature work, debugging, or explanation workflows before implementation.
3. **Prove agent work**: run deterministic checks, affected-test routing, and test-change detection before human review.

## Non-Goals

- Replacing code review, product judgment, architecture judgment, or tests.
- Guaranteeing model correctness or runtime behavior inside every external harness.

## External Systems

| System | Why it exists | Interface owner | Failure fallback |
| --- | --- | --- | --- |
| Git | Worktree, diff, branch, hook, and changed-file detection | Beryl Control Plane | Fall back to broad project checks or report unavailable Git state |
| Agent runtimes and IDEs | Consume generated root instruction shims | Root Contracts | Keep canonical `.beryl/agent/` files as source of truth and resync shims |
| Optional browser tooling | Verify web UI and generated output behavior | Host project adapter | Report browser verification unavailable and run closest deterministic check |

## Definition Of Done

A feature is complete only when it has all of the following:

1. A small design artifact update (`design-tree.md` and/or ADR) when design changes.
2. Clear boundary types/interfaces (where language supports this).
3. Behavior tests plus at least one edge case test.
4. Deterministic checks run (`./.beryl/scripts/check.sh` and relevant project checks).
5. No new illegal boundary crossings.
