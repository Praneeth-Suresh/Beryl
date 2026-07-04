# Ubiquitous Language

| Business Term | Technical Symbol | Definition | Constraints | Avoid |
| --- | --- | --- | --- | --- |
| Design Concept | `DesignConcept` | The shared organizing model guiding architecture and implementation choices. | Must be coherent across contexts. | `Idea`, `GeneralModel` |
| Design Tree | `DesignTree` | Living map of open and settled decisions. | Updated when design moves. | `PlanDump` |
| Bounded Context | `BoundedContext` | A domain boundary with explicit ownership and language. | Owns its internal model and API. | `Module` (too generic) |
| Ubiquitous Language | `UbiquitousLanguage` | Shared domain vocabulary in docs and code. | Terms must be stable and explicit. | Ambiguous nouns like `Data` |
| Feedback Loop | `FeedbackLoop` | Generate-check-fix cycle using deterministic tools. | Must include real tool output. | `TryAgainLoop` |
| Success Check | `SuccessCheck` | Pre-coding acceptance condition that proves a plan, redirect, feature slice, or bug fix worked. | Must name the expected artifact, deterministic command, generated output or browser evidence when applicable, and at least one user-visible behavior. | Vague done criteria such as `LooksGood` |
| Commit Boundary | `CommitBoundary` | Proposed repo-history unit for implementation work. | Must have one purpose, expected files, and a validating check command; should not mix generated output, docs, tests, and source unless required. | Large mixed commit |
| Agent-Ready Repository | `AgentReadyRepository` | A repository with versioned agent instructions, task routing, deterministic checks, visible review artifacts, and clear human ownership before agent work begins. | Must be backed by repo files and commands, not only prompt advice. | `AI-enabled repo`, `Agentic vibe` |
| Hard Guarantee Layer | `HardGuaranteeLayer` | Repository-installed process controls that make agent expectations, checks, generated contracts, and review boundaries inspectable. | Guarantees process visibility and deterministic gates, not model correctness. | `Safety magic`, `Correctness guarantee` |
| Runtime Harness | `RuntimeHarness` | CLI, IDE, plugin, or execution environment that loads and runs an agent session. | Beryl may generate contracts for harnesses but does not own their runtime behavior. | Treating harness behavior as repository state |
| Skill Pack | `SkillPack` | Reusable runtime-loaded agent behavior instructions. | Useful beside Beryl; not the same as repository governance. | Calling Beryl just a skill pack |
| Generated Output | `GeneratedOutput` | Built artifact, copied asset, static HTML, feed, sitemap, robots file, search index, or similar file users or crawlers receive. | Static-site changes must verify affected generated output, not source alone. | Source-only verification |
| Affected Test Gate | `.beryl/scripts/check-affected.sh` | Commit and manual check step that maps changed files to related tests or full-test fallback. | Must be deterministic and run through `.beryl/scripts/check.sh`. | Ad hoc local test picking |
| Full Test Fallback | `FULL_TEST_CMD` | Complete project test command used when a change is too broad to select related tests safely. | Configured in `.beryl/agent/affected-tests.conf`. | Silent skip for broad changes |
| Setup Script | `.beryl/scripts/setup-project.sh` | Interactive onboarding command that installs the agent control plane into a target project. | Must offer deterministic defaults and explicit AI fallback. | Manual multi-file setup checklist |
| AI Agent Fallback | `run_agent_fallback` | Opt-in setup path that hands project-specific configuration to a selected headless coding agent. | Prompt must be user-provided and not stored in tracked files. | Hidden automation |
| Entropy Hotspot | `EntropyHotspot` | High-churn and high-complexity area likely to degrade maintainability. | Used for targeted refactoring. | `MessyFile` |
| Extraction Slice | `ExtractionSlice` | One safe, non-feature refactor step identified after reading changed files from a product run. | Must preserve behavior, avoid new features, name the files involved, and identify the protecting check or missing regression test. | Broad cleanup, opportunistic redesign |
| Vertical Slice | `VerticalSlice` | Smallest end-to-end behavior change through one boundary. | Must be testable in isolation. | `BigRefactor` |
| Adapter | `Adapter` | Boundary object that isolates external systems from domain logic. | Domain must not depend on vendor details. | `ServiceHelper` |
| Seam | `Seam` | Intentional change point for behavior substitution without invasive edits. | Should be protected by tests. | `HackPoint` |
| ADR | `ADR` | Architecture Decision Record for durable decisions. | Required for lasting boundary changes. | `RandomNote` |
| Beryl Root | `BERYL_ROOT` | Absolute path to the installed `.beryl` control-plane directory. | Use only for Beryl-owned implementation files and manifest/config reads. | Treating it as the host repo root |
| Repo Root | `REPO_ROOT` | Absolute path to the host project repository root that contains `.beryl`. | Use for Git operations, host scans, root shims, and test manifests. | Treating it as the Beryl implementation root |
| Component | `Component` | Installable Beryl capability such as `agent-core`, `checks`, `githooks`, `ci`, or `driver`. | Declared in `.beryl/beryl.components.json`; dependencies resolve before install. | Ad hoc copy bundle |
| Profile | `Profile` | Named component selection such as `minimal`, `standard`, or `full`. | Must resolve through the same dependency graph as explicit components. | Separate setup mode |
| Component Manifest | `ComponentManifest` | `.beryl/beryl.components.json`, the source of truth for components, profiles, paths, root contracts, and hooks. | Parsed by installer, setup, and validator. | Duplicated component lists |
| Agent Context Seed | `AgentContextSeed` | Generic template files copied into `.beryl/agent/` during install for project-owned brief, architecture, design, testing, vocabulary, and ADR context. | Must not contain Beryl's own product or architecture decisions. Existing target files are preserved unless the seed conflict policy allows overwrite. | Copying Beryl's development docs into target repos |
| Lockfile | `.beryl/lock.json` | Installed component record written after a successful installer run. | Records requested components, resolved dependencies, source ref, source label, and installer version. | Hidden install state |
