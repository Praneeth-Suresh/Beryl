---
name: creating-illustrations
description: Use when a structure, flow, sequence, state machine, dependency graph, or comparison would be clearer as a diagram than as prose. Produces accurate, readable, text-based diagrams.
---

# Creating Illustrations

## Purpose

Show the shape of a system, change, or decision when words alone make the
reader rebuild it in their head.

## When To Draw

Draw when the reader needs to see relationships: call flows, data flow, module
boundaries, state transitions, dependency order, timelines, or before/after
structure. Do not draw a diagram that only repeats a short list.

## Choose The Form

| Content | Form |
| --- | --- |
| Steps over time between actors | Mermaid `sequenceDiagram` |
| Components and their dependencies | Mermaid `flowchart` |
| States and transitions | Mermaid `stateDiagram-v2` |
| Data entities and relations | Mermaid `erDiagram` |
| Ordered work with dependencies | Mermaid `flowchart` or `gantt` |
| Options compared on several dimensions | Markdown table |
| Custom layout Mermaid cannot express | Hand-written SVG |

Prefer Mermaid in Markdown. It is text, renders on GitHub, and is reviewable in
a diff. Use SVG only when Mermaid cannot express the layout. Do not use ASCII
art for anything with more than a few boxes.

## Accuracy

1. Draw only what you verified. Every box and arrow must map to a real file,
   module, function, service, or decision. Use the names from the code.
2. Label arrows with what flows or why: a call name, a message, an event.
3. If part of the diagram is a proposal or a guess, mark it, for example with a
   dashed edge or a `(proposed)` label, and say so in the text.
4. Put the source paths for the main nodes in the text below the diagram.

## Readability

- Keep to about 12 nodes. Split a larger picture into an overview plus one
  diagram per area.
- Use one direction of flow, such as top to bottom or left to right.
- Group related nodes with `subgraph` instead of adding colour.
- Do not rely on colour alone to carry meaning. Use labels or line styles too.
- Keep labels short. Put detail in the text below.
- In SVG, include a `<title>` and `<desc>`, use readable font sizes, keep
  contrast high, and do not load external fonts, images, or scripts.

## Output

1. One sentence that says what the diagram shows.
2. The diagram.
3. A short key or notes: source paths, anything proposed or uncertain, and
   anything left out on purpose.
