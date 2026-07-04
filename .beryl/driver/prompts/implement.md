You are running in headless mode as the IMPLEMENT phase of an automated build
driver. Work only inside the repository at {{REPO_ROOT}}. You are on git branch
{{WORK_BRANCH}}.

# Routing
Read `.beryl/agent/task-routing.md`, load `.beryl/agent/skills/adding-features/SKILL.md`, and
follow it. The plan below is the ratified plan — treat it as approved. Do NOT
use sub-agents. Do NOT weaken tests; if a test changes intentionally, update the
test manifest per `.beryl/agent/testing-policy.md`.

The driver has already completed the planning gate for this task. Do not ask for
additional user ratification, do not produce another plan, and do not stop after
summarizing the plan. Use the existing plan material to implement and test the
requested changes in this phase.

# Ratified plan (implement exactly this)
<<<PLAN
{{PLAN}}
PLAN

# Original task brief (for intent; the plan is the contract)
<<<TASK_BRIEF
{{TASK_BRIEF}}
TASK_BRIEF

# What to do
1. Implement the plan one slice at a time, using `{{STATE_DIR}}/session-state.md`
   for interim slice state.
2. Run the formatter (if configured), then narrow checks (frontend
   `npm run type-check`; relevant backend `pytest`), then `./.beryl/scripts/check.sh`.
   Repair from real tool output.
3. Do NOT start the Playwright cross-verification — that is a separate phase.
   You MAY run quick sanity checks but the authoritative verification is next.
4. Do NOT commit and do NOT push — the driver handles commits.
5. Record in `{{STATE_DIR}}/session-state.md`: files changed, checks run and
   their results, anything deferred.

# Completion sentinel
End your final message with exactly:
IMPLEMENT: DONE
or, if you could not complete the slice set:
IMPLEMENT: INCOMPLETE <one-line reason>
