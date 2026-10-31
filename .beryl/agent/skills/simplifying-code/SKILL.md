---
name: simplifying-code
description: Use when code in a specific module or area is hard to understand or change, when the user asks to simplify, refactor, clean up, or improve the design or architecture of some code, or when a maintenance program hands over a refactor slice. Finds unmanaged complexity from evidence and removes it with small, behavior-preserving changes.
---

# Simplifying Code

## Purpose

Reduce the complexity that makes code hard to understand and change, using
established software design principles that fit the code's language and
paradigm. The goal is code that a new reader can change safely, not code that
follows a pattern for its own sake.

Complexity shows up in three ways:

- **Change amplification:** one small change needs edits in many places.
- **Cognitive load:** a reader must hold too much in their head to make a change.
- **Unknown unknowns:** it is not clear what code or which assumptions a change will affect.

Every finding must point at one of these.

## Scope

Use this for one module, package, class hierarchy, feature area, or file set.
For a whole-repository assessment, use `maintaining-codebase` first; it hands
individual slices to this skill.

Do not change behavior. Do not add features. Do not reformat or rename code
that is outside the agreed scope.

## 1. Understand Before Judging

1. Read `.beryl/agent/architecture.md` and `.beryl/agent/ubiquitous-language.md`
   for boundaries and domain terms.
2. Identify the language, its dominant paradigm in this codebase
   (object-oriented, functional, procedural, or mixed), and the local
   conventions: naming, error handling, module layout, dependency injection,
   and test style. Existing conventions win over textbook preferences unless
   they cause one of the three complexity symptoms.
3. Read the callers, the tests, and recent history (`git log -p` on the area)
   to learn why the code looks the way it does. Treat odd code as possibly
   deliberate until you find out otherwise.
4. Find what protects the current behavior: tests, type checks, contracts.
   Note any gaps.

## 2. Find Problems From Evidence

Look for these, and record the file and line, the symptom, and why it hurts:

| Problem | What it looks like |
| --- | --- |
| Shallow module | The interface is about as complex as the implementation; callers must know internal details to use it. |
| Pass-through layer | A method or class only forwards calls and adds no abstraction. |
| Information leak | The same knowledge, such as a format, an ordering rule, or a magic value, is spread across several modules. |
| Temporal coupling | Callers must call things in a particular order that nothing enforces. |
| Low cohesion | One unit mixes unrelated responsibilities; edits for unrelated reasons keep landing in it. |
| High coupling | A unit depends on another's internals, or a change in one forces a change in the other. |
| Duplicated logic | The same rule is implemented twice and can drift. Duplicated text that encodes different rules is not duplication. |
| Inheritance misuse | Deep or wide hierarchies, subclasses that override to disable behavior, or base classes used only to share helpers. |
| Leaky dependencies | Domain logic depends on HTTP objects, ORM records, UI state, or vendor types instead of an adapter. |
| Hidden side effects | A function that looks like a query also writes state, does I/O, or mutates its inputs. |
| Overly general code | Configuration, hooks, or abstraction layers with a single user and no planned second one. |
| Unclear names | Names that do not match the ubiquitous language, or one concept with several names. |
| Error-handling sprawl | The same error is caught and rethrown at many layers, or errors are silently swallowed. |

Use tools when they exist: the linter, type checker, complexity or duplication
reports, `./.beryl/agent/scripts/entropy-hotspots.sh` for churn, and the test
suite. Say which evidence was unavailable. Do not invent metrics.

## 3. Choose The Principle That Fits

Pick the fix from the principle that matches the problem and the paradigm.
Prefer the smallest change that removes the symptom.

General:

- Make modules deep: a small, simple interface hiding a large implementation.
- Hide information: put each design decision in exactly one module.
- Define errors out of existence where possible, for example by making an
  operation safe to repeat instead of making every caller check first.
- Keep one level of abstraction per function.
- Prefer explicit data flow over shared mutable state.
- Delete code that has no caller.

Object-oriented code:

- Give each class one reason to change.
- Prefer composition over inheritance. Use inheritance only for a real
  "is-a" relation that honors the base class's contract.
- Depend on small interfaces the caller owns, not on concrete classes from
  another context.
- Keep objects valid after construction; avoid "call init() before use".
- Tell objects what to do instead of pulling their data out to decide for them.

Functional code:

- Keep a functional core of pure functions and push I/O to a thin outer shell.
- Model states with types so invalid states cannot be represented.
- Compose small functions instead of adding flags to large ones.
- Keep data immutable at module boundaries.

Procedural and scripting code:

- Group related data and the functions that act on it into one module.
- Replace long parameter lists with a named structure.
- Validate input once at the boundary, then trust it inside.

Do not apply a pattern because it is named. Each change must remove a
symptom you recorded in step 2.

## 4. Propose

Present a short, ordered list of changes. For each one, give:

- the problem, with its location and evidence;
- the principle and the concrete change;
- the expected effect on change amplification, cognitive load, or unknown unknowns;
- the test or check that proves behavior is unchanged, and any test that must
  be added first;
- the risk, and how to roll it back.

Order the list so that each change is safe on its own, adding protecting
tests before the refactor that needs them. Stop and wait for the user to
approve before editing.

## 5. Apply One Change At A Time

After approval:

1. If the protecting test is missing, add it first and confirm it passes
   against the current code.
2. Make one change. Keep public behavior, outputs, and error cases the same.
3. Run the formatter, the narrow check, then the broader check.
4. Use `verification-before-completion` before reporting the change as done.
5. Repeat for the next approved change.

If a change turns out to need a behavior change, stop and say so. If a durable
boundary moved, add a line to the Decision Record in
`.beryl/agent/architecture.md`.

## Rules

- Never weaken a test to make a refactor pass.
- Never mix a refactor with a behavior change in the same commit.
- Do not introduce a new dependency or framework to simplify code; use
  `composing-modules` if one seems necessary.
- Do not claim the code is "clean" or that complexity is gone. Report what
  changed and what remains.

## Output

Follow `communicating-with-users`. Report the findings with evidence, the
approved changes made, the checks run and their results, and the problems
left for later.
