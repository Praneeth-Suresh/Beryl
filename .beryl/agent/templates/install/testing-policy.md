# Testing Policy

## Command Matrix

| Check | Command | Status | Notes |
| --- | --- | --- | --- |
| Markdown sanity | `./.beryl/scripts/check-md.sh` | available | Unclosed fences and tabs |
| Test manifest immutability check | `./.beryl/scripts/check-tests-unchanged.sh` | available | Detects changes in configured test scope from `.beryl/agent/test-manifest.conf` |
| Affected test gate | `./.beryl/scripts/check-affected.sh --worktree` | available | Selects related tests from changed files and uses full-test fallback for broad changes |
| Aggregate deterministic gate | `./.beryl/scripts/check.sh` | available | Runs all deterministic checks |
| Format | `not available yet` | unavailable | Add the project formatter command when configured |
| Lint | `not available yet` | unavailable | Add the project lint command when configured |
| Typecheck | `not available yet` | unavailable | Add the project typecheck command when configured |
| Unit tests | `not available yet` | unavailable | Add the project unit test command when configured |
| Integration tests | `not available yet` | unavailable | Add the project integration test command when configured |
| E2E smoke | `not available yet` | unavailable | When web runtime exists, use Microsoft Playwright MCP for deterministic browser feedback |

## Default Loop

1. Identify or add the failing behavior.
2. Select the smallest useful test level.
3. State success checks before implementation: expected artifact, narrow command, broader command, generated output or browser evidence when applicable, and one user-visible behavior.
4. Implement one internal feature slice.
5. Run narrow checks first, then broader checks.
6. Repair from actual tool output.
7. For web UI or HTML/CSS work, include a Playwright MCP browser verification step.

## Generated Output Verification

For static-site changes, source inspection is not enough. Always verify generated output that users, crawlers, or downstream tooling receive.

Check affected:

- Relevant `dist` HTML or equivalent built pages.
- Sitemap, robots, search index, feed, or structured data output.
- Copied assets when asset handling changed.
- Browser behavior when UI, routing, or layout changed.

If generated output is unavailable, explain why and run the closest deterministic build or inspection command.

## Affected Test Gate

Commit-time tests run through the affected test gate so developers get fast feedback without choosing test subsets manually.

- The pre-commit hook sets `CHECK_AFFECTED_MODE=staged` and runs `./.beryl/scripts/check.sh`.
- Manual `./.beryl/scripts/check.sh` uses worktree mode by default and selects from all changes relative to `HEAD`.
- `.beryl/scripts/check-affected.sh` reads `.beryl/agent/affected-tests.conf`.
- Changes to broad configuration, dependency, hook, or test-strategy files force `FULL_TEST_CMD` when configured.
- Source and test changes run `RELATED_TEST_CMD` with changed files appended when configured.
- If no project test runner is configured yet, the gate reports that no project tests are available and exits successfully.

Recommended project configurations:

```bash
# Jest
RELATED_TEST_CMD=(npx --no-install jest --findRelatedTests --passWithNoTests)
FULL_TEST_CMD=(npm test)

# pytest with testmon
RELATED_TEST_CMD=(pytest --testmon)
FULL_TEST_CMD=(pytest)
```

## Test Modification Rule

Existing tests may not be weakened to make implementation pass.

Intentional test changes are allowed only when all conditions are met:

1. The behavior change is explicit in the task or design artifact.
2. `./.beryl/scripts/update-test-manifest.sh` is run after the intentional change.
3. The manifest update is committed with the test change.
4. The final response explains why tests changed.
5. `.beryl/agent/test-manifest.conf` is updated if new test locations/patterns are introduced.

## Immutability Enforcement Scope

- The SHA manifest mechanism provides deterministic change detection, not cryptographic immutability guarantees against privileged users.
- Enforce stronger controls in CI/review policy, such as branch protection, required status checks, and code review.

## Mocking Rules

- Mock external systems such as network, clocks, randomness, payment providers, and email providers.
- Do not mock domain logic in the same bounded context.
