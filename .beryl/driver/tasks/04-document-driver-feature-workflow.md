# Task 04 - Document how users can populate and run driver tasks

## Goal

Explain in more detail how users can use the driver to carry out a list of feature tasks step by step.

## Context

Users need a clearer path from describing desired work to having the driver execute numbered task briefs. The "Adding Feature" section should explain how the recording agent can populate the `.beryl/driver/tasks` directory before the driver is run.

## Requirements

1. Add a subheading under the README's "Adding Feature" section.
2. Explain that users can first tell the recording agent they want a list of tasks completed.
3. Explain that users can ask the recording agent to populate `.beryl/driver/tasks` with those tasks as numbered task briefs.
4. Explain that once the directory is populated, users can run the driver script to carry out tasks step by step.
5. Include a hyperlink to the README inside the `driver` directory for more details.

## Acceptance checks

1. The new subheading appears under the "Adding Feature" section.
2. The workflow is understandable without prior knowledge of the driver internals.
3. The link to the driver README resolves correctly.
4. Markdown sanity checks pass.
5. The broader repository check passes.

## Out of scope

- Changing driver behavior.
- Creating new driver commands.
- Reorganizing README sections beyond what is needed for this explanation.
