You are running in headless mode as the PLAN phase of an automated build driver.
Work only inside the repository at {{REPO_ROOT}}. You are on git branch
{{WORK_BRANCH}}.

# Routing
First read `agent/task-routing.md`, classify this as planning, and load
`agent/skills/planning/SKILL.md`. Then load only the canonical files that
workflow asks for (project-brief, design-tree, architecture, ubiquitous-language,
testing-policy, agent-rules) as needed. Do NOT use sub-agents.

# Your task brief (the authoritative outcome to plan toward)
<<<TASK_BRIEF
{{TASK_BRIEF}}
TASK_BRIEF

# Attempt context
This is attempt {{ATTEMPT}} of {{MAX_ATTEMPTS}}.
{{FAILURE_CONTEXT}}

# What to do
1. Investigate the relevant code before planning. Read the real files; do not guess.
2. Produce a small, reviewable, slice-based implementation plan that fully
   satisfies the task brief, including the explicit verification criteria the
   brief lists under "Acceptance / Playwright checks".
3. If this is a re-plan after a failed verification, your plan MUST directly
   address every reason listed in the failure context above. Call out what
   changed from the previous plan.
4. Do NOT edit any implementation code in this phase.

# Required output (write to files — this is how the next phase gets context)
- Overwrite `{{STATE_DIR}}/plan.md` with the full plan:
  requested outcome, bounded context, approach, slice list (no IDs exposed to
  user), files to change, tests/checks to run, and the exact Playwright checks
  that will prove success.
- Append a dated entry to `{{STATE_DIR}}/session-state.md` summarizing this
  plan and (if a re-plan) what you changed and why.

# Completion sentinel
When the plan is written, end your final message with a line exactly:
PLAN: READY
If you cannot form a viable plan, end with:
PLAN: BLOCKED <one-line reason>
