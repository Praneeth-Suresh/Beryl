# Task 05 - Reset driver tasks and state to general placeholders

## Goal

Change the tasks in the driver tasks folder to placeholder tasks instead of real product tasks, and refresh state files so no previous task material remains.

## Context

The driver should be safe to use as a reusable workflow. Task briefs and runtime state should not contain material from previous real tasks after this cleanup.

## Requirements

1. Replace real task content in the tasks folder with general placeholder task content.
2. Refresh all driver state files so they do not contain plans, verification notes, attempts, or session material from previous tasks.
3. Remove or reset any material that might have been used in previous tasks.
4. Keep only general content in task files at the end.
5. Preserve the directory structure and any files required for the driver to run.

## Acceptance checks

1. Every task file contains only general placeholder content.
2. Driver state files contain only empty, reset, or generic state appropriate for a fresh run.
3. No previous real task names, routes, plans, verification results, or logs remain in active task or state files.
4. The driver status command can run without errors.
5. Markdown sanity checks pass.

## Out of scope

- Deleting the driver itself.
- Changing the driver state machine.
- Removing documented examples from committed documentation unless they are active task or state material.
