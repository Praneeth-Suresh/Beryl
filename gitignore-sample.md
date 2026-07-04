# Agent Control Plane Gitignore Sample

Use these patterns in your `.gitignore` to keep the agent-specific infrastructure, documentation, and generated instruction shims out of your repository while keeping only your project's codebase.

Add this only when the code is going to move to production. This is because until then you will need to version the agent's knowledge base so that evolutions to the agent's implementation can be studied.

```gitignore
# --- Agent Control Plane ---
# The core logic and documentation for agent behavior
/.beryl/

# --- Agent Documentation ---
# Local documentation files provided by the boilerplate
/Practise.md
/Theory.md
/Cheatsheet.md
/README.md

# --- Instruction Shims & Generated Files ---
# Tool-specific instructions and generated shims (synced from .beryl/agent/ folder)
/AGENTS.md
/CLAUDE.md
/.codex/
/.cursor/rules/agent-rules.md
/.github/copilot-instructions.md

# --- Agent State & Manifests ---
# Deterministic check state that should not be part of the codebase logic
/.beryl/agent/session-state.md
/tests/.manifest.sha256
```
