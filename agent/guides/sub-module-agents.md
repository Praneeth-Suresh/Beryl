# Sub-Module Agent Structure

Use this when a project has multiple complex sub-modules that each need their own design decisions, domain language, and testing commands.

## When To Use

- Monorepo with 3+ independently deployable services or packages.
- Sub-modules with different tech stacks or domain vocabularies.
- A single root `agent/` has become too broad for agents to load efficiently.

## When NOT To Use

- Projects with fewer than 3 bounded contexts (the root `agent/` is sufficient).
- Sub-modules that share the same domain language, architecture, and test commands.

**Enforced**: `init-module-agent.sh` refuses to create sub-module agents unless 3+ bounded contexts are declared in root `agent/architecture.md`. `module-doctor.sh` warns if fewer than 3 module agents exist.

## Structure

```
repo-root/
  agent/                          ← root (global rules, shared language, skills, scripts)
  modules/
    billing/
      agent/                      ← module-level (billing-specific decisions)
        module-context.md
        project-brief.md
        design-tree.md
        architecture.md
        ubiquitous-language.md
        testing-policy.md
        adr/
      src/
    identity/
      agent/                      ← module-level (identity-specific decisions)
        ...
      src/
```

## What Lives Where

| Concern | Root `agent/` | Module `agent/` |
| --- | --- | --- |
| Engineering rules | ✓ (authoritative) | inherits |
| Security policy | ✓ (authoritative) | inherits |
| Skills | ✓ (shared) | inherits |
| Scripts | ✓ (shared) | inherits |
| Project brief | whole-system goal | module goal |
| Design tree | cross-module decisions | module-internal decisions |
| Architecture | module map + cross-module boundaries | internal module structure |
| Ubiquitous language | shared terms | module-local terms |
| Testing policy | root gate commands | module-specific commands |
| ADRs | cross-module decisions | module-internal decisions |

## Create A Sub-Module Agent

```bash
# Ensure the module directory exists
mkdir -p modules/billing

# Scaffold the agent structure
./agent/scripts/init-module-agent.sh modules/billing billing "Plans, invoices, subscription state"
```

Then fill the generated files with real content.

## Register The Module In Root Architecture

After creating a module agent, update root `agent/architecture.md`:

```md
## Bounded Contexts

| Context | Owns | Does Not Own | Public Entry Point |
| --- | --- | --- | --- |
| billing | Plans, invoices, subscription state | Auth, notifications | modules/billing/src/index.ts |
| identity | Login, sessions, members, roles | Billing rules | modules/identity/src/index.ts |
```

## Validate All Modules

```bash
# Check root agent health
./agent/scripts/agent-doctor.sh

# Check all sub-module agent structures
./agent/scripts/module-doctor.sh
```

## Agent Prompt For Module Work

When asking an agent to work inside a specific module:

```text
Working in: modules/billing

[feature/bug/plan request]

Read modules/billing/agent/module-context.md for scope and precedence.
Use the module's agent/ files for module-specific context.
Use root agent/ for skills, rules, and scripts.
Run the module's check command first, then ./scripts/check.sh.
```

## Cross-Module Feature Prompt

```text
This feature touches modules/billing and modules/identity.

Read each module's agent/module-context.md.
Changes to module internals follow that module's agent/ files.
Interface changes between modules follow root agent/architecture.md.
New shared terms go in root agent/ubiquitous-language.md.
If a boundary changes, create a root-level ADR.
```

## Managing Sub-Module Agents Over Time

### Adding a new module

```bash
mkdir -p modules/new-module
./agent/scripts/init-module-agent.sh modules/new-module new-module "Domain description"
# Fill files, update root architecture.md, run module-doctor.sh
```

### Splitting a module

1. Create the new module agent structure.
2. Move relevant ADRs from the old module.
3. Update both modules' `architecture.md` and `ubiquitous-language.md`.
4. Update root `architecture.md` with the new boundary.
5. Create a root ADR explaining the split.

### Merging modules

1. Choose which module's agent structure survives.
2. Merge the other module's design-tree decisions and language into the survivor.
3. Remove the defunct module's `agent/` directory.
4. Update root `architecture.md`.
5. Create a root ADR explaining the merge.

### Weekly maintenance

```bash
# Run entropy hotspots per module
cd modules/billing && ../../agent/scripts/entropy-hotspots.sh

# Or from root, check all modules
./agent/scripts/module-doctor.sh
```

## Precedence Summary

1. Explicit user instructions.
2. Module `agent/` files (for module-specific concerns).
3. Root `agent/` files (for shared rules, skills, scripts, security).
4. Existing code and conventions.

Module files override root files only for: project-brief, design-tree, architecture, ubiquitous-language, and testing-policy. Everything else is inherited from root.
