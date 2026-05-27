# Interview Me

## Purpose

Interview the user about a plan or design uncertainty until the next decision is clear.

This skill is adapted from Matt Pocock's productivity `grill-me` skill, but is intentionally named `interview-me` here so it does not replace the framework's structured `grill-me` critique.

## Trigger Conditions

- `grill-me` aborts because required user judgment is missing.
- `grill-me` returns an assumption that cannot be validated from repository files.
- A plan has multiple viable branches and the choice depends on product, UX, delivery, or risk preference.

Do not use this skill for facts that can be discovered by reading code, tests, configs, logs, or canonical agent files.

## Process

1. State the unresolved decision in one sentence.
2. Explore the repository first if the answer might be discoverable.
3. Ask exactly one focused question.
4. Provide the recommended answer and why it is the default.
5. Wait for the user's answer before asking the next question.
6. Continue down the decision tree until the plan can proceed or must be blocked.
7. Return the resolved decision to the calling workflow.

## Output Template

```yaml
skill: interview-me
status: "<resolved|blocked>"
unresolved_decision: "<question being resolved>"
recommended_answer: "<default recommendation>"
user_answer: "<answer or pending>"
decision_effect: "<how this changes the plan>"
next_action: "<continue-plan|rerun-grill-me|block>"
```

## Rules

- Ask one question at a time.
- Prefer a recommended default over open-ended questioning.
- Keep questions concrete and tied to the current plan.
- Do not ask the user to answer repository facts.
- Do not update implementation code.
- Do not use sub-agents unless the user explicitly asks for them.

