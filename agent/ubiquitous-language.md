# Ubiquitous Language

| Business Term | Technical Symbol | Definition | Constraints | Avoid |
| --- | --- | --- | --- | --- |
| Design Concept | `DesignConcept` | The shared organizing model guiding architecture and implementation choices. | Must be coherent across contexts. | `Idea`, `GeneralModel` |
| Design Tree | `DesignTree` | Living map of open and settled decisions. | Updated when design moves. | `PlanDump` |
| Bounded Context | `BoundedContext` | A domain boundary with explicit ownership and language. | Owns its internal model and API. | `Module` (too generic) |
| Ubiquitous Language | `UbiquitousLanguage` | Shared domain vocabulary in docs and code. | Terms must be stable and explicit. | Ambiguous nouns like `Data` |
| Feedback Loop | `FeedbackLoop` | Generate-check-fix cycle using deterministic tools. | Must include real tool output. | `TryAgainLoop` |
| Success Check | `SuccessCheck` | Pre-coding acceptance condition that proves a plan, redirect, feature slice, or bug fix worked. | Must name the expected artifact, deterministic command, generated output or browser evidence when applicable, and at least one user-visible behavior. | Vague done criteria such as `LooksGood` |
| Affected Test Gate | `scripts/check-affected.sh` | Commit and manual check step that maps changed files to related tests or full-test fallback. | Must be deterministic and run through `scripts/check.sh`. | Ad hoc local test picking |
| Full Test Fallback | `FULL_TEST_CMD` | Complete project test command used when a change is too broad to select related tests safely. | Configured in `agent/affected-tests.conf`. | Silent skip for broad changes |
| Setup Script | `scripts/setup-project.sh` | Interactive onboarding command that installs the agent control plane into a target project. | Must offer deterministic defaults and explicit AI fallback. | Manual multi-file setup checklist |
| AI Agent Fallback | `run_agent_fallback` | Opt-in setup path that hands project-specific configuration to a selected headless coding agent. | Prompt must be user-provided and not stored in tracked files. | Hidden automation |
| Entropy Hotspot | `EntropyHotspot` | High-churn and high-complexity area likely to degrade maintainability. | Used for targeted refactoring. | `MessyFile` |
| Extraction Slice | `ExtractionSlice` | One safe, non-feature refactor step identified after reading changed files from a product run. | Must preserve behavior, avoid new features, name the files involved, and identify the protecting check or missing regression test. | Broad cleanup, opportunistic redesign |
| Vertical Slice | `VerticalSlice` | Smallest end-to-end behavior change through one boundary. | Must be testable in isolation. | `BigRefactor` |
| Adapter | `Adapter` | Boundary object that isolates external systems from domain logic. | Domain must not depend on vendor details. | `ServiceHelper` |
| Seam | `Seam` | Intentional change point for behavior substitution without invasive edits. | Should be protected by tests. | `HackPoint` |
| ADR | `ADR` | Architecture Decision Record for durable decisions. | Required for lasting boundary changes. | `RandomNote` |
