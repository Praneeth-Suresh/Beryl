# Using Beryl

## Purpose

Set up Beryl in a target repository, then use its repository-owned workflow and
deterministic checks for subsequent work.

## Remote Skill Entry Point

Use this skill from the target repository. Do not require the user to clone
Beryl first.

Canonical skill URL:

```text
https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/.beryl/agent/skills/using-beryl/SKILL.md
```

For repeatable setup, replace `main` in all Beryl GitHub URLs with the trusted
tag or commit SHA selected by the user. If no ref is specified, use `main` and
report that the setup used a moving ref.

## Setup

1. Confirm the current working directory is the target repository. Never clone
   Beryl into or beside the target unless the user explicitly asks for a local
   Beryl checkout workflow.
2. Inventory existing repository state before install:
   - application code, tests, package/build files, and docs
   - existing `.beryl/`
   - existing agent instruction files such as `AGENTS.md`, `CLAUDE.md`,
     `.codex/AGENTS.md`, `.cursor/rules/agent-rules.md`,
     `.github/copilot-instructions.md`, `.cursorrules`, `.windsurfrules`, and
     similar tool-specific files
   - existing workflow files under `.github/workflows/`
3. Download the installer for the selected ref:

   ```bash
   BERYL_REF=main
   curl --proto '=https' --tlsv1.2 -fsSL \
     "https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/$BERYL_REF/install.sh" \
     -o beryl-install.sh
   ```

   On Windows, use PowerShell only to download the file, then run it from Git
   Bash or WSL.
4. Install Beryl into the current repository. Start with conflict-preserving
   root behavior in existing repositories:

   ```bash
   sh beryl-install.sh --ref "$BERYL_REF" --interactive --root-conflict skip
   ```

   Use `--bootstrap-agent` only when the user wants a supported coding agent to
   fill project-specific Beryl context.
5. Consolidate existing agent guidance into Beryl:
   - Treat `.beryl/agent/` as the canonical home for durable agent rules,
     project brief, architecture, testing policy, vocabulary, and workflow
     routing.
   - Move or summarize durable guidance from pre-existing agent files into the
     smallest matching `.beryl/agent/` canonical file. Preserve project-specific
     meaning; do not paste stale or tool-specific boilerplate wholesale.
   - Keep application code, tests, docs, package files, and unrelated workflows
     outside Beryl.
   - Do not delete or overwrite existing non-Beryl files without explicit user
     approval. If a root agent file conflicts, preserve its content first, then
     ask before replacing it with a generated Beryl shim.
6. Regenerate Beryl-managed agent shims after consolidation:

   ```bash
   BERYL_SHIM_CONFLICT=skip ./.beryl/agent/scripts/sync-agent-env.sh
   ```

   If existing root instruction files intentionally need replacement, get
   explicit user approval first, then rerun:

   ```bash
   BERYL_SHIM_CONFLICT=overwrite ./.beryl/agent/scripts/sync-agent-env.sh
   ```
7. Configure tests only from discovered project commands. Do not invent host
   project test commands or configuration.
8. Run checks from the target repository:

   ```bash
   ./.beryl/scripts/check.sh
   ```

   Report missing prerequisites or unavailable checks instead of claiming that
   the target is verified.

## Updating Beryl

Use the downloaded `install.sh` to update an existing target only after
confirming that `TARGET/.beryl/lock.json` exists. The default update retains
the lockfile's `requestedComponents`; pass `--profile` or `--components` only
when the user explicitly wants to replace that requested feature selection.

```bash
BERYL_REF=v1.2.3
sh beryl-install.sh --ref "$BERYL_REF" --update --target /path/to/target
```

For a remote update, ask the user for a trusted tag or commit SHA when none is
provided, and use `--expected-sha256` when they supply a trusted release
archive digest. Do not describe a moving ref such as `main` as repeatable.

The updater stages and validates the selected release, then updates only its
file-level managed surface. It preserves target-owned canonical agent context,
custom configuration, driver tasks and state, and user-added files. A
successful update retains replaced files under `.beryl/.updates/<timestamp>/`.
If it fails, report the structured phase/component/path/reason/rollback output
and do not claim the update succeeded.

## Working With Beryl

1. Read `.beryl/agent/task-routing.md` and load the one matching workflow
   skill before editing.
2. For feature work, present a plan and wait for approval before implementing.
3. Follow the target repository's canonical agent rules and testing policy.
4. Run the narrow relevant check, then `./.beryl/scripts/check.sh`, and report
   the changed files and results for review.

## References

- Remote README:
  `https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/README.md`
- Remote scripts reference:
  `https://raw.githubusercontent.com/Praneeth-Suresh/Beryl/main/.beryl/scripts/README.md`
- Installed agent control plane: `.beryl/agent/README.md`
# Update bootstrap safety

When updating an installation, do not pass `--bootstrap-agent`; complete the transactional update first and run bootstrap as a separate action.
