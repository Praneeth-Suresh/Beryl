# Task 03 - Clarify repository Markdown file purposes in the README

## Goal

Make it clearer to users what the different Markdown files in the repository are for and how they can be used as reference material.

## Context

The repository contains many Markdown files. The root README does not currently explain their purposes clearly enough for users who need to know which files to read or update.

## Requirements

1. Review the Markdown files that are visible to normal repository users.
2. Update the README with a clear guide to the purpose of the important Markdown files.
3. Explain which files are user-facing documentation, which files are agent instructions, and which files are reference or design material.
4. Describe when a user should consult each file.
5. Keep the README concise and useful rather than duplicating the full contents of each referenced file.

## Acceptance checks

1. README readers can identify the purpose of each important Markdown file without opening every file first.
2. Links or paths in the README point to the correct files.
3. Markdown sanity checks pass.
4. The broader repository check passes.

## Out of scope

- Rewriting every Markdown file.
- Changing agent workflow rules unless the README clarification reveals a broken reference.
- Adding generated documentation.
