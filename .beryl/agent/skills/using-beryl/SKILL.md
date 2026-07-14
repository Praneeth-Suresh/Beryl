# Using Beryl

## Purpose

Set up Beryl in a target repository, then use its repository-owned workflow and
deterministic checks for subsequent work.

## Setup

1. Read [README.md](../../../../README.md) and
   [Quickstart.md](../../../../Quickstart.md). Use
   [the scripts reference](../../../scripts/README.md) for install flags,
   profiles, bootstrap controls, prerequisites, and troubleshooting.
2. Choose the setup entry point that fits the available source:
   - From a Beryl checkout, run
     `./.beryl/scripts/setup-project.sh /path/to/project`.
   - For a remote install, use the inspected, ref-pinned installer command in
     the README.
   - Use `--bootstrap` only when the user wants a supported coding agent to
     fill project-specific context.
3. Preserve existing target files unless the setup flow explicitly asks to
   replace them. Do not invent host-project test commands or configuration.
4. After setup, run `./.beryl/scripts/check.sh` from the target repository.
   Report missing prerequisites or unavailable checks instead of claiming that
   the target is verified.

## Working With Beryl

1. Read `.beryl/agent/task-routing.md` and load the one matching workflow
   skill before editing.
2. For feature work, present a plan and wait for approval before implementing.
3. Follow the target repository's canonical agent rules and testing policy.
4. Run the narrow relevant check, then `./.beryl/scripts/check.sh`, and report
   the changed files and results for review.

## References

- [Quickstart.md](../../../../Quickstart.md): first-run path.
- [Scripts reference](../../../scripts/README.md): complete installation and
  setup commands.
- [Agent control plane](../../README.md): canonical instruction layout and
  bootstrap checklist.
