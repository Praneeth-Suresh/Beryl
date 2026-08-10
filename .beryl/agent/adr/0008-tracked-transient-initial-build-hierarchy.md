# ADR 0008: Track A Transient Initial-Build Hierarchy

## Status

Accepted

## Context

Large greenfield applications need more coordination than a single feature plan. An agent must clarify the request, discover the repository, decompose the work into dependent deliverables, and preserve enough context to resume after interruption. A hidden prompt or ignored scratch file cannot provide a reliable reviewable record across sessions and worktrees.

The execution hierarchy is useful while the initial build is active, but it is not durable project context. Keeping it permanently would mix progress bookkeeping with the canonical design, architecture, vocabulary, and testing documents.

## Decision

Add an installable, model-neutral `initial-build` workflow under `.beryl/agent/skills/`. Explicit large or greenfield requests use this route; ordinary feature, debugging, and explanation requests keep their existing routes. The workflow asks clarification questions one at a time, performs repository discovery before proposing work, and presents a hierarchical dependency plan for explicit user ratification.

Only after ratification does the agent create `.beryl/agent/hierarchy.md`. The file is Git-tracked so an active build is visible, reviewable, and resumable across sessions and worktrees. Each node records a stable id, parent, dependencies, deliverable, acceptance checks, status, and canonical context targets. The agent implements dependency-ready nodes in order and updates the hierarchy and relevant canonical Markdown as it progresses.

The hierarchy enters the first build commit authorized by the user, and later hierarchy updates are committed with their corresponding implementation slices. The agent verifies tracked state rather than equating an unignored working-tree file with a tracked file. The final authorized build commit includes both the hierarchy deletion and the last durable context promotions.

Before completion, the agent promotes durable decisions, boundaries, terminology, and verification knowledge to canonical context files. Completion requires every node and required check to pass. Only then does the agent delete `hierarchy.md`; the deletion safeguard has a narrow exception for this declared transient artifact. A pre-existing hierarchy always resumes the active initial build rather than starting a second plan.

## Consequences

- **Benefit:** Active large builds have a visible, reviewable, resumable execution path.
- **Benefit:** Installed repositories receive one workflow that is independent of any particular model, CLI, or plugin.
- **Benefit:** Durable context survives hierarchy deletion without preserving temporary progress noise.
- **Tradeoff:** The workflow relies on agent instruction-following; deterministic checks can verify the file contract but cannot guarantee model behavior.
- **Tradeoff:** Git history records the temporary hierarchy while it exists, even though the completed working tree no longer contains it.
- **Follow-up:** Add a deterministic contract check for the workflow and deletion lifecycle.
