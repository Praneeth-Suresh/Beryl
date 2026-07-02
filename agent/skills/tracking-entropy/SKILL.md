# Tracking Entropy

## Purpose

Find high-risk change hotspots and define small, targeted refactoring actions.

## Trigger Conditions

- Weekly maintainability review
- After a long product run
- Request for one safe extraction slice
- Before major feature work
- Repeated edits in the same files
- Request to assess technical debt or complexity

## Input Contract (required)

```yaml
skill: tracking-entropy
time_window: "12.month"
active_contexts:
  - "<context>"
changed_files:
  - "<path or use git status/diff>"
known_pain_points:
  - "<optional>"
```

## Process

1. Run `agent/scripts/entropy-hotspots.sh`.
2. Identify high-churn files/modules.
3. Analyze top candidate for mixed concepts, boundary crossings, and test protection.
4. Propose one small refactor that lowers future context load.
5. Defer opportunistic cleanup outside scope.

## Post-Run Extraction Mode

Use this mode when the user references a long product run, changed files, cleanup after feature work, or asks for one safe extraction slice.

Rules:

- Do not implement new features.
- Read the changed files before proposing the extraction slice.
- Consider dead selectors, repeated CSS patterns, rendering functions that should be split, generated artifacts that should not be hand-edited, and tests missing for known regressions.
- Return one safe extraction slice only.
- If there is no safe extraction slice, return `status: abort` with `reason_code: "no-safe-extraction-slice"`.

## Output Template (required)

```yaml
skill: tracking-entropy
status: success
time_window_used: "<window>"
hotspot_candidates:
  - path: "<file>"
    churn_rank: 1
chosen_hotspot:
  path: "<file>"
  why_selected: "<reason>"
post_run_findings:
  dead_selectors:
    - "<selector or none>"
  repeated_css_patterns:
    - "<pattern or none>"
  rendering_functions_to_split:
    - "<function or none>"
  generated_artifacts_not_to_hand_edit:
    - "<path or none>"
  missing_regression_tests:
    - "<behavior or none>"
risk_reduction_hypothesis: "<what gets easier>"
smallest_next_refactor_step: "<single step>"
safe_extraction_slice: "<single behavior-preserving extraction step>"
tests_to_add_or_verify:
  - "<path or command>"
notes: "<short rationale>"
```

## Success Criteria

- Output uses the exact template keys.
- Hotspot list and chosen hotspot are both present.
- Next refactor step is concrete and bounded.
- Safe extraction slice is concrete, bounded, and behavior-preserving when post-run extraction mode is used.
- Tests to protect the refactor are identified.
- Post-run findings are based on changed-file evidence when post-run extraction mode is used.

## Refusal / Abort Conditions

Return this template when aborting:

```yaml
skill: tracking-entropy
status: abort
reason_code: "<no-history|no-hotspots|scope-too-broad|no-safe-extraction-slice>"
missing_or_blocked:
  - "<item>"
required_user_input: "<single next clarification>"
```

Abort if:

- Repository history is unavailable for churn analysis.
- No meaningful hotspot can be identified in the requested window.
- Refactor request is broad and cannot be reduced to one safe step.
- Post-run extraction review cannot identify a behavior-preserving slice from changed files.

## File Update Permissions

- May update: `agent/design-tree.md`, `agent/adr/*`
- Must not perform broad implementation changes in the same step unless explicitly requested
