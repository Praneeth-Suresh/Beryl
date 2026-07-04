# Beryl Brand Guide

## Core Identity

Beryl is positioned as the **hard guarantee layer that makes repositories ready for agents**.
The brand should feel intentional, precise, and operational: clean geometry, strong contrast,
minimal ornamentation, and visible evidence of control.

The product is not "another skill pack." Beryl sits around the repository. It makes the
repo declare its agent contract, routes work through explicit workflows, and backs claims
with deterministic local gates.

## Color Tokens

Use these tokens as the default palette source for new brand surfaces and UI accents.

- `--beryl-emerald-50` — `#ECFDF5`
- `--beryl-emerald-100` — `#D1FAE5`
- `--beryl-emerald-300` — `#6EE7B7`
- `--beryl-emerald-400` — `#34D399`
- `--beryl-emerald-500` — `#10B981`
- `--beryl-emerald-600` — `#0F766E`
- `--beryl-emerald-700` — `#047857`
- `--beryl-emerald-800` — `#065F46`
- `--beryl-emerald-900` — `#064E3B`

## Typographic Direction

For documentation and website surfaces, pair:

- Display/heading: a sans-serif with geometric traits (for example, `Inter`).
- Body: a practical, readable sans-serif (for example, `Inter`, `Inter Tight`, or `IBM Plex Sans`).

Type should feel like infrastructure documentation rather than AI marketing. Prefer direct
headlines, short nouns, and concrete mechanisms over aspirational language.

## Logo Tokens and Variants

Current repo assets:

- Full color mark: `assets/beryl-logo.svg`
- Square mark: `assets/beryl-logo-square.svg`
- Monochrome mark: `assets/beryl-logo-monochrome.svg`
- Inverted mark: `assets/beryl-logo-inverted.svg`
- Favicon mark: `assets/favicon.svg`
- Social preview: `assets/beryl-social-preview.svg`

## Usage Rules

- Keep a clear space of roughly `0.25x` the logo width around all edges.
- Do not stretch, skew, or rotate the logo.
- Do not add extra outer strokes, glow, or rounded-corner wrappers around the mark.
- Avoid placing the full-color logo on similarly saturated green backgrounds.
- Prefer full-color on light/neutral backgrounds and inverted variant on dark backgrounds.

## Sizing Baseline

- Full logo minimum: `220px` width on docs or screens
- Square/monochrome variants minimum: `64px` width
- Favicon: `48x48` rendered from `assets/favicon.svg`

## Content and Copy Anchors

Across documentation and landing surfaces, lead with:

- one-line role statement:
  - "Hard guarantees for agent-ready repositories."
- then a one-liner on outcome:
  - "Install the repository contract agents must follow."

## Messaging Pillars

- Repository readiness: Beryl prepares the repository before an agent starts work.
- Hard guarantees: Beryl turns agent instructions, checks, manifests, and review gates into files and scripts that can be inspected.
- Runtime agnostic: Beryl can work beside skill packs, IDE assistants, and headless CLIs because the source of truth lives in the repo.
- Human-owned review: Beryl makes evidence visible; it does not replace engineering judgment.
- Deterministic feedback: Beryl favors explicit local checks over session-only claims.

## Differentiation Language

Use this framing when comparing Beryl with adjacent agent tooling:

- "Skill packs improve agent behavior inside a session. Beryl prepares the repository around that session."
- "Runtime harnesses make the agent more capable. Beryl makes the repo more auditable."
- "Beryl does not ask teams to trust a chat transcript. It gives them files, scripts, manifests, and checks."
- "Use smarter agents if you want. Beryl is the control plane that keeps their work reviewable."

Avoid these claims:

- "Beryl makes agents safe."
- "Beryl guarantees correct code."
- "Beryl replaces tests, code review, or architecture judgment."
- "Beryl competes with every skill framework."

Preferred claim:

- "Beryl gives repositories hard, inspectable process guarantees around agent work."

## Future Brand Improvements to Track

- Add an official typeface pair in `README` examples and package docs.
- Keep a consistent local color token file for docs, website, and diagrams.
- Add a small "Brand Usage" checklist to release and PR templates when adding surfaces.
