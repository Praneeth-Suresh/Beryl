# Bootstrap status artifact schema

The bootstrap command writes `.beryl/agent/bootstrap-status.json` with these keys:

- `timestamp`: ISO-8601 UTC time when status is written.
- `installer_version`: install flow version string.
- `source_ref`: installer source reference used.
- `profile/components.profile`: selected profile name (if any).
- `profile/components.components`: components resolved for this install/target.
- `runner`: runner name used (`codex`, `claude`, `custom`, or `off`).
- `runner_version`: reported version string for codex/claude; `custom` for custom runner.
- `status`: one of `already-complete`, `manual`, `completed`, `partial`, `failed`.
- `missing_files`: list of required `.beryl/agent/*.md` files still missing/unfilled.
- `filled_files`: list of required `.beryl/agent/*.md` files already filled.
- `errors`: list of verification/runner errors.
- `command`: rendered runner command or guidance token.
