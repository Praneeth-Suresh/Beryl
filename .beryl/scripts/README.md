# Deterministic Checks

Single entrypoint:

```bash
./.beryl/scripts/check.sh
```

## Interactive Project Setup

For a new project, run:

```bash
./.beryl/scripts/setup-project.sh /path/to/project
```

The script copies the agent control plane, configures `.beryl/agent/affected-tests.conf`, syncs generated instruction shims, creates the initial test manifest, and can enable `.beryl/githooks/pre-commit`.

When the listed stack or test-runner options are not enough, choose `Use AI agent fallback`. The script will ask for a project/setup prompt and run Codex, Claude, or a custom headless command from inside the target project.

`check.sh` runs:

1. `check-md.sh`
2. `check-tests-unchanged.sh`
3. `check-project.sh` (project-specific extension point)

`check-project.sh` delegates to the affected test gate:

```bash
./.beryl/scripts/check-affected.sh --worktree
```

The gate reads `.beryl/agent/affected-tests.conf`.

- Configure `RELATED_TEST_CMD` for test runners that can select tests from changed files.
- Configure `FULL_TEST_CMD` for broad changes that should run the whole project test suite.
- Leave both empty until the project has a real test runner; the gate will report that no project tests are configured and keep the deterministic checks passing.

Examples:

```bash
# Jest
RELATED_TEST_CMD=(npx --no-install jest --findRelatedTests --passWithNoTests)
FULL_TEST_CMD=(npm test)

# pytest with testmon
RELATED_TEST_CMD=(pytest --testmon)
FULL_TEST_CMD=(pytest)
```

## Test Immutability (Detection)

This repo uses a committed SHA-256 manifest over a configurable test scope.

- Scope is configured in `.beryl/agent/test-manifest.conf` via:
  - `MANIFEST_PATH`
  - `INCLUDE_GLOBS`
  - `EXCLUDE_GLOBS`
- `./.beryl/scripts/check-tests-unchanged.sh` fails if any file in the configured scope differs from the manifest.
- If a test change is intentional, update the manifest:

```bash
./.beryl/scripts/update-test-manifest.sh
```

Commit both the test changes and the updated manifest together.

This mechanism provides deterministic detection of test changes. It does not create absolute immutability against privileged repository writes.

## Run On Every Commit (Optional)

This repo includes a git hook at `.beryl/githooks/pre-commit`.

Enable it locally:

```bash
git config core.hooksPath .beryl/githooks
```

The hook runs `./.beryl/scripts/check.sh` with `CHECK_AFFECTED_MODE=staged`, so project tests are selected from the files staged for that commit. Manual `./.beryl/scripts/check.sh` uses worktree mode and selects from all changes relative to `HEAD`.
