# Task 08 - Ship a short, story-style onboarding quickstart linked from the README

## Goal

Give a first-time user one short, fun, and clear document that gets them from "I just installed
Beryl" to "I ran my first agent task safely" without reading the whole `Cheatsheet.md`. Distill the
essential getting-started path into a snappy, story-style quickstart and hyperlink it prominently
from `README.md`.

## Context

Beryl's real getting-started knowledge lives in `Cheatsheet.md`, which is thorough (~30KB) but dense:
install, configure the test manifest, enable the hook, optional CI, first prompts, per-feature
workflow, debugging, and skill selection. `README.md` has a "Quick Start" section (install commands,
`./.beryl/scripts/check.sh`, `setup-project.sh`) and a "Documentation Map" that links to
`Theory.md`, `Practise.md`, `Cheatsheet.md`, and others, but there is no gentle on-ramp: a newcomer
must parse reference material to learn the happy path.

The project voice is confident and plain (see `README.md` and `assets/brand/beryl-brand-guide.md`
for tone). The desired quickstart is intentionally different in register from the reference docs:
short, witty, story-framed, and visual, while still being accurate and pointing back to the
canonical docs for depth. This depends on Task 07's outcome: once the operating contract loads
automatically, the quickstart should teach the *simple* prompt, not the old boilerplate block.

## Requirements

1. Create a new standalone Markdown file for onboarding (for example `Quickstart.md` at the repo
   root, or `docs/quickstart.md`; pick one and keep it consistent with the repo's existing doc
   layout). It must be a distillation of `Cheatsheet.md`, not a copy.
2. Frame it as a short, story-style walkthrough with a clear single goal: instruct the reader how to
   get started working with Beryl. Follow one narrative arc, for example a developer handing a repo
   to an agent and using Beryl's gates, rather than a flat reference list.
3. Cover only the essential first-run path and keep it skimmable: install into a repo, run
   `./.beryl/scripts/check.sh`, optionally enable the pre-commit hook, and the plan -> ratify ->
   implement loop with a *bare* modern prompt (relying on the auto-loaded operating contract from
   Task 07, not the removed boilerplate).
4. Make it interesting and easy to read: keep it short (aim for a few minutes to read), witty but
   not noisy, and use visuals where they help. Reuse the repo's existing visual conventions
   (Markdown tables, fenced code blocks, and at least one Mermaid diagram like the ones in
   `README.md`), and reference brand assets under `assets/` where a logo or preview image fits.
5. Every command and file path in the quickstart must be correct and match the current scripts and
   layout under `.beryl/`. Do not invent commands.
6. End with a short "where to go deeper" pointer back to `Cheatsheet.md`, `Practise.md`,
   `Theory.md`, and the relevant `.beryl/agent/` docs so the quickstart stays lean.
7. Make the `README.md` more concise. When a new user who wants to find out about the repository reads through the `README.md`, they should be shown only what they need but everything they need to know. They should not be given unecessary texts or essays that don't affect them. People's attention is dififcult to grab so be sure to be attention grabbing because the `README.md` is where people make a decision about the product.
8. Hyperlink the quickstart prominently from `README.md`: add it near the top of the "Quick Start"
   section (and to the "Documentation Map") as the recommended first read, with a one-line
   description consistent with the map's existing entry style.
9. Keep the quickstart consistent with the auto-loaded operating contract from Task 07: it must not
   reintroduce the instruction boilerplate that Task 07 removes.

## Acceptance checks

1. A new onboarding Markdown file exists, is clearly a distilled quickstart (materially shorter than
   `Cheatsheet.md`), and reads as a short story-style narrative with a single stated goal of getting
   started with Beryl.
2. The file includes visuals consistent with the repo (at least one Mermaid diagram and at least one
   table or annotated code block) and stays skimmable.
3. Every command and path in the file is valid against the current repository (install command,
   `./.beryl/scripts/check.sh`, hook enablement, `setup-project.sh`, and any `.beryl/agent/` paths
   referenced).
4. `README.md` links to the quickstart from both the Quick Start area (as the recommended first
   read) and the Documentation Map, and the links resolve.
5. The quickstart teaches the bare, auto-loaded prompt style and does not restate the operating
   contract that Task 07 removed from `Cheatsheet.md`.
6. `./.beryl/scripts/check.sh` passes, including markdown checks and any link/reference checks.

## Out of scope

- Deleting or shrinking `Cheatsheet.md`, `Theory.md`, or `Practise.md`; the quickstart supplements
  them and links back for depth.
- Building a docs site, adding a static-site generator, or introducing new tooling to render docs.
- Creating new brand assets; reuse existing files under `assets/`.
- Changing installer, scripts, or agent instruction behavior (that is Task 07's territory

# Task 08 - Placeholder task

## Goal

Replace this placeholder with one specific task brief before running the driver for real work.

## Context

This file is part of the reusable driver workflow. It intentionally contains no project-specific implementation request, route, plan, verification result, or prior session material.

## Requirements

1. Replace this placeholder with a concrete task outcome.
2. Keep the task scoped to one reviewable change.
3. Include clear acceptance checks before execution.
4. Keep runtime notes in the driver state directory, not in the task brief.

## Acceptance checks

1. The placeholder has been replaced before executing real work.
2. The task brief contains only the task-specific context needed for that work.
3. The driver can discover the numbered task file.

## Out of scope

- Preserving material from previous driver runs.
- Adding project-specific implementation details to this placeholder.
