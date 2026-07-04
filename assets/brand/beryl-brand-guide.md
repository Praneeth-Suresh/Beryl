# Beryl Brand Guide

## Core Identity

Beryl is positioned as a **control-plane product for reliable AI-assisted engineering**.
The brand should feel intentional, precise, and operational: clean geometry, strong contrast,
and minimal ornamentation.

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
  - "Inspectable control plane for AI-assisted software engineering."
- then a one-liner on outcome:
  - "Structure, checks, and traceability for stochastic contributors."

## Future Brand Improvements to Track

- Add an official typeface pair in `README` examples and package docs.
- Keep a consistent local color token file for docs, website, and diagrams.
- Add a small "Brand Usage" checklist to release and PR templates when adding surfaces.
