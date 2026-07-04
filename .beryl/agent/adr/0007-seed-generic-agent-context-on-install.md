# ADR 0007: Seed Generic Agent Context On Install

## Status

Accepted

## Context

Beryl installs into other repositories. The install manifest previously copied `.beryl/agent/` as a whole, which meant target repositories received Beryl's own project brief, architecture, design tree, vocabulary, and ADR history as their canonical agent context.

Those files are correct for developing Beryl itself, but wrong as installed target project truth.

## Decision

Keep Beryl's filled-in canonical files in `.beryl/agent/` for this repository. Add generic install seed templates under `.beryl/agent/templates/install/` and run `.beryl/agent/scripts/seed-agent-context.sh` as an `agent-core` post-install hook.

The component manifest must install reusable control-plane files explicitly instead of using a broad `.beryl/agent/` copy. The seed hook writes target-owned canonical files from templates and preserves existing target files unless `BERYL_AGENT_TEMPLATE_CONFLICT=overwrite` is set.

## Consequences

- **Benefit:** Fresh target repositories get generic, fillable agent context instead of Beryl-specific design decisions.
- **Benefit:** Beryl keeps its own repository-specific source of truth for local development.
- **Tradeoff:** The installer has one more post-install hook and a second conflict policy for target-owned agent context.
- **Follow-up:** Keep install seed templates generic whenever canonical agent files change.
