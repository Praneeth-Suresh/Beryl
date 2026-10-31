---
name: refreshing-context
description: Use when the user asks to refresh, review, audit, or clean up the agent context files, periodically (for example monthly), or after a large change to the repository such as a restructure, migration, or major feature. Checks the context layer against the code, quizzes the developer to confirm what is still true, and removes or fixes redundant and misleading context with approval.
---

# Refreshing Context

## Purpose

Keep the context layer in `.beryl/agent/` true, short, and useful. Agents
trust these files, so a stale or misleading line costs more than a missing
one. This skill finds drift between the context and the code, checks it with
the developer, and removes or fixes what is wrong.

The context layer is the project-owned files in `.beryl/agent/`:

- `project-brief.md`
- `architecture.md` (boundaries, design concept, open decisions, decision record, pressure points)
- `ubiquitous-language.md`
- `testing-policy.md`
- the same files in module `agent/` directories, when the repository has them

Other files in `.beryl/agent/`, such as `agent-rules.md`, `task-routing.md`,
`security-policy.md`, and the skills, are managed by Beryl and replaced on
update. Report problems in them to the user instead of editing them, except in
the Beryl source repository itself.

## When To Run

- The user asks to refresh, review, or clean up context.
- On a regular cadence, such as monthly.
- After a large change: a restructure, a migration, a renamed domain concept,
  a new or removed bounded context, or a big feature.
- When an agent finds that a context file contradicts the code.

## 1. Gather Evidence

Do this before asking the developer anything. Do not edit files in this step.

1. Run `./.beryl/agent/skills/refreshing-context/scripts/context-drift.sh`.
   It reports paths named in context files that no longer exist, how much code
   changed since each context file was last updated, and top-level directories
   that no context file mentions. Treat its output as leads, not verdicts.
2. Read each context file. For each claim that can be checked, check it
   against the code: do the named modules, entry points, commands, and adapters
   exist and work as described? Do the glossary terms appear in the code, and
   does the code use other names for the same concepts?
3. Look at what changed since the context was last updated:
   `git log --since=<date> --stat`. Note new areas, removed areas, and renames.
4. Sort every finding into one of these:

| Kind | Meaning | Default action |
| --- | --- | --- |
| Broken | Names a file, command, or module that does not exist. | Fix or remove. |
| Contradicted | The code does something different from what the file says. | Ask which is right. |
| Redundant | Says the same thing as another file, or repeats what the code or tooling already enforces. | Remove the copy. |
| Generic | Advice that applies to any project and teaches a capable model nothing. | Remove. |
| Missing | An important area, boundary, or term with no context. | Ask whether to add it. |
| Unverifiable | A claim the code cannot confirm, such as intent or priorities. | Ask. |

## 2. Quiz The Developer

Turn the findings that need human judgement into a short quiz. The quiz checks
that the context matches what the developer believes, and it surfaces
knowledge that is only in their head. Keep it light and quick to answer.

- Ask in rounds of up to five questions. Number them so the developer can
  answer in one line, such as "1 true, 2 b, 3 skip".
- Mix question types:
  - **True or false:** quote a line from a context file and ask if it is still true.
  - **Which is right:** show what the file says and what the code does, and ask which one should win.
  - **Spot the stale line:** show three short claims and ask which one is out of date.
  - **Name it:** show a code concept that has no glossary entry and ask what the team calls it.
  - **Still a rule?:** quote a rule and ask whether it still earns its place.
- Give your recommended answer under each question, based on the evidence, so
  the developer can accept it with "yes".
- Say where each question comes from (file and line, and the code evidence).
- After each round, give a one-line score of how many lines were confirmed,
  fixed, or removed, and say how many questions are left. Stop when the user
  asks, or after three rounds, and offer to continue another time.
- If an answer contradicts the code, say so and ask whether the code or the
  context is wrong. A wrong code finding is a bug or a plan, not a context edit.

Do not ask about facts you can check yourself.

## 3. Propose The Edits

List every change before making it, grouped by file:

- what to delete, and why;
- what to rewrite, with the new text;
- what to add, with the new text;
- what to move, such as a decision from prose into one line in the Decision Record.

Prefer deleting over rewording. Context should be the shortest text that stops
an agent from making a mistake. Keep one source for each fact; where two files
overlap, keep the line in the file that owns it and delete the other.

Follow the deletion safeguard in `agent-rules.md`: list what is removed and
where any replacement lives, then wait for explicit approval.

## 4. Apply And Verify

After approval:

1. Make the edits.
2. If `tool-instruction-template.md` changed, run
   `./.beryl/agent/scripts/sync-agent-env.sh`.
3. Run the context drift script again and confirm the broken entries are gone.
4. Run `./.beryl/agent/scripts/agent-doctor.sh` and `./.beryl/scripts/check.sh`
   (`--development` in the Beryl source checkout).

## Rules

- Never change code to match the context in this workflow. Report the
  mismatch and route it to `planning` or `systematic-debugging`.
- Do not edit vendored skills listed in `.beryl/agent/skills/VENDORED.md`.
- Do not add progress notes or a log of this refresh to the context files.
  The commit message records what changed.
- Keep the developer's answers as the source of truth for intent. Keep the
  code as the source of truth for behavior.

## Output

Follow `communicating-with-users`. Report the quiz results, the edits made per
file, lines removed and added, the checks run, and any mismatch that needs a
code change.
