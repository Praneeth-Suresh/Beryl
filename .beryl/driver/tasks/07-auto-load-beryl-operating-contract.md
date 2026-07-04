# Task 07 - Auto-load the Beryl operating contract so users stop repeating it

## Goal

Make Beryl's standing operating rules apply to every agent session automatically, so a user gets
correct behavior from a bare prompt like "implement the approved feature plan" without pasting the
recurring instruction block. Then remove that now-redundant boilerplate from the prompt templates in
`Cheatsheet.md`.

## Context

Today `Cheatsheet.md` teaches users to append an operating block to feature prompts, for example:

```text
Use .beryl/agent/task-routing.md and the adding-features workflow.
Manage implementation steps internally in .beryl/agent/session-state.md if needed.
Run the formatter command, narrow checks, then ./.beryl/scripts/check.sh.
Clear temporary session state when the feature is complete.
Do not weaken tests. If tests change intentionally, update the test manifest.
Do not use sub-agents unless I explicitly ask for them.
```

Most of this contract already lives in the canonical instruction source
`.beryl/agent/tool-instruction-template.md` and in `.beryl/agent/agent-rules.md`, and the generated
root shims (`AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`,
`.github/copilot-instructions.md`, `.codex/AGENTS.md`) are produced from the template by
`.beryl/agent/scripts/sync-agent-env.sh`. The problem is not that the rules are absent; it is that
they are not stated crisply enough as always-on defaults, and the Cheatsheet still tells users to
restate them, which trains users to think the instructions are required input.

Two specifics in the block are weaker than the rest in the canonical files:

- The explicit ordering "run the formatter command, then narrow checks, then
  `./.beryl/scripts/check.sh`" is only implied by the generic "narrow checks, then broader checks"
  step.
- "If tests change intentionally, run `./.beryl/scripts/update-test-manifest.sh` (update the test
  manifest) and explain why" appears in Cheatsheet prompt copy but is not stated as a standing rule
  in `agent-rules.md`.

## Requirements

1. Treat `.beryl/agent/tool-instruction-template.md` as the canonical instruction source. Make the
   full operating contract an explicit, always-on default there: default task-routing +
   `adding-features` for ratified feature work, internal use of `.beryl/agent/session-state.md`,
   the formatter -> narrow checks -> `./.beryl/scripts/check.sh` ordering, clearing temporary session
   state on completion, never weakening tests, updating the test manifest via
   `./.beryl/scripts/update-test-manifest.sh` when tests change intentionally, and no sub-agents
   unless the user explicitly asks.
2. State clearly that these defaults apply even when the user does not mention them, and that a user
   only needs to speak up to opt out or override (for example to allow sub-agents).
3. Mirror the same standing rules into `.beryl/agent/agent-rules.md` so the canonical rule file and
   the template agree. In particular add the formatter -> narrow -> `check.sh` ordering and the
   intentional-test-change manifest-update rule if they are not already explicit there.
4. Regenerate the root instruction shims from the template with
   `.beryl/agent/scripts/sync-agent-env.sh` so every generated shim
   (`AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`,
   `.codex/AGENTS.md`) carries the same defaults. Do not hand-edit the generated shims.
5. In `Cheatsheet.md`, remove the operating-contract boilerplate from the prompt templates that
   currently repeat it (the new-project implementation prompt in section 6, and the feature
   implement / continue / resume / debugging prompts). Reduce each affected prompt to the
   task-specific intent (what to build or fix) plus any genuine per-request choice, and replace the
   removed lines with a short one-time note that the operating contract is loaded automatically from
   `.beryl/agent/` and only needs mentioning to override it.
6. Keep the opt-in escape hatches discoverable: the note must still tell users how to allow
   sub-agents or otherwise deviate from a default for a single prompt.
7. Do not change what the rules mean or make them stricter; only relocate them so they load by
   default and deduplicate the Cheatsheet copy.

## Acceptance checks

1. `.beryl/agent/tool-instruction-template.md` states every item of the operating contract as an
   always-on default, including the formatter -> narrow -> `check.sh` ordering and the
   test-manifest-update rule, and says the defaults apply without the user restating them.
2. `.beryl/agent/agent-rules.md` agrees with the template on those defaults with no contradiction.
3. Running `.beryl/agent/scripts/sync-agent-env.sh` leaves all five generated shims byte-identical to
   the template (`git diff` shows the shims match the regenerated source, and `sync-agent-env.sh`
   reports no pending changes on a second run).
4. `Cheatsheet.md` no longer instructs users to paste the operating-contract block into feature,
   continue, resume, or debugging prompts; the affected prompts contain only task-specific intent
   plus a single reference that the contract loads automatically and how to override it.
5. A reader following the trimmed Cheatsheet prompts, plus the auto-loaded instructions, would still
   get routing, session-state handling, the check sequence, test-manifest discipline, and the
   no-sub-agents default.
6. `./.beryl/scripts/check.sh` passes (markdown checks, component manifest, test-manifest detection,
   project checks).

## Out of scope

- Changing skill contracts under `.beryl/agent/skills/` or the task-routing decision logic.
- Changing what `./.beryl/scripts/check.sh`, the formatter, or the affected-test gate actually run.
- Adding a new instruction-loading mechanism or runtime; reuse the existing template + shim sync.
- Rewriting `Theory.md`, `Practise.md`, or `README.md` beyond links already required elsewhere.
