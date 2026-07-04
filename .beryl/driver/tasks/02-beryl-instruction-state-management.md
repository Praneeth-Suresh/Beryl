# Task 02 - Verify agent instruction and state management after `/.beryl` reorganization

## Goal

Ensure that after the repository reorganization under the `/.beryl` directory, all agent instructions and runtime state can still be effectively managed.

## Context

The repository has been reorganized so agent-owned instructions and state may now live under `/.beryl`. The driver and agents must still be pointed at the correct instruction and state locations.

## Requirements

1. Audit the repository for references to the previous instruction or state locations.
2. Confirm the active agent entry points load instructions and state from the correct `/.beryl` location.
3. Confirm driver prompts, scripts, generated shims, and state files refer to the correct location.
4. Fix any broken or stale references immediately.
5. Preserve existing behavior for the driver and normal agent workflows.

## Acceptance checks

1. Run the narrow checks that prove the instruction and state paths resolve correctly.
2. Run the repository's broader deterministic check command.
3. Confirm a fresh agent or driver phase would read the expected instruction and state files.
4. Confirm no stale references to obsolete instruction or state paths remain unless documented as intentional compatibility shims.

## Out of scope

- Changing unrelated agent workflow semantics.
- Redesigning the driver state machine.
- Moving additional files beyond what is required to make `/.beryl` management work.
