# Explaining Codebase

## Purpose

Explain how a codebase area works without changing files.

## Process

1. Restate the question and scope.
2. Load only the canonical files needed to understand names, boundaries, and architecture.
3. Inspect the smallest relevant set of source files.
4. Explain the flow through public interfaces first, then internals.
5. Call out bounded contexts, adapters, tests, and design documents that anchor the explanation.
6. Mention uncertainties or files not inspected.

## Rules

- Do not edit files.
- Do not load unrelated workflows.
- Do not use sub-agents unless the user explicitly asks for them.

## Final Response

- Short answer
- Key files and responsibilities
- Runtime or data flow
- Tests/checks that cover the behavior, if found
- Open questions or risks
