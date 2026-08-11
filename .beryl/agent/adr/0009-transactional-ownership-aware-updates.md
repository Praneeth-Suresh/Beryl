# ADR 0009: Use Transactional, Ownership-Aware Installation Updates

## Status

Accepted

## Context

An installed Beryl control plane accumulates two different kinds of content:
Beryl runtime files that should receive fixes and features, and target-owned
project context, configuration, driver tasks/state, and user-added files that
must survive an update. Replacing broad `.beryl/` directories would erase
target knowledge. A previous lockfile recorded selected components but could
not identify individual Beryl-owned files, while remote failures or hooks could
leave an installation only partially changed.

## Decision

Make `install.sh --update --target DIR` the Beryl Control Plane's public update
interface. It requires `DIR/.beryl/lock.json` and, unless `--profile` or
`--components` is passed explicitly, reuses the lockfile's requested component
selection. Explicit selection replaces the recorded requested selection and
then resolves dependencies.

Before updating, the installer validates the component manifest, stages the
selected source surface, expands it into a file-level managed-path ledger, and
snapshots every target path and hook output it can mutate. The manifest owns
`updatePreservePaths`: exact target-owned paths and slash-suffixed subtrees
that must not be updated. The new lockfile records `managedPaths` only after
apply, declared hooks, and staged-file verification all succeed.

The transaction may update or remove only ledger-owned files. It preserves
manifest-declared context and configuration as well as unknown user content.
Legacy lockfiles that have no managed-path ledger migrate conservatively: files
in the newly staged surface are treated as managed for replacement, but no old
path is deleted. Successful updates retain replaced snapshots under
`.beryl/.updates/<timestamp>/`. A failure rolls the snapshot back and reports
the phase, component, path, reason, and rollback result in one structured
diagnostic.

Remote update guidance is to pin `--ref` to a trusted tag or commit SHA and
use `--expected-sha256` with an archive digest obtained from a trusted release
channel. A moving ref is allowed by the installer but is not repeatable.

## Consequences

- **Benefit:** Beryl runtime updates do not require directory-level replacement
  or overwriting project-owned context.
- **Benefit:** The lockfile makes update ownership inspectable and supports
  safe removal of files no longer present in the selected surface.
- **Benefit:** Staging, snapshots, rollback, and retained successful backups
  make failures and changed content recoverable.
- **Tradeoff:** Updates need a valid existing lockfile; users cannot apply them
  to arbitrary `.beryl/` directories.
- **Tradeoff:** Legacy installations retain stale managed files rather than
  risking deletion of user-modified content.
- **Tradeoff:** A successful update may retain backup data until the repository
  owner removes it deliberately.
