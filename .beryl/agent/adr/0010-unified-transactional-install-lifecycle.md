# ADR 0010: Use One Transactional Install Lifecycle Engine

## Status

Accepted

## Supersedes

This ADR supersedes the installation-lifecycle portions of ADR 0003, ADR 0005,
and ADR 0009. The component-manifest and generic-agent-context decisions in
those ADRs remain in force where they do not conflict with this lifecycle
contract.

## Context

Beryl exposes both a direct installer and a setup command. Their separate
copying, conflict, lockfile, hook, and rollback behavior allowed the same
target to reach incompatible lifecycle states. In particular, an initial
installation could mutate a target before all conflicts and runtime
requirements were known, and setup could create an installation that the
updater could not recognize.

An installer also crosses a hostile filesystem boundary. A target, a
pre-existing `.beryl` directory, a root contract, or an ancestor can be a
symbolic link. Following one while probing, creating directories, changing
modes, or replacing a file can mutate an external location. A successful
lifecycle operation must therefore make its ownership and rollback boundaries
inspectable before it changes the repository.

## Decision

The public lifecycle surface is `install.sh` for initial installation, locked
update, restore, conservative uninstall, explicit adoption, and standalone
bootstrap. This ADR records the implemented lifecycle architecture.

`install.sh` is the Beryl Control Plane's sole lifecycle mutation
engine. `.beryl/scripts/setup-project.sh` will collect interactive or
non-interactive choices and delegate one normalized request to `install.sh`;
it must not independently copy files, write a lockfile, modify Git
configuration, or enable hooks.

Initial installation and update use the same ownership-ledger transaction
contract:

1. Parse and validate options, source, required runtimes, and the component
   manifest before target mutation. Every remote lifecycle source uses a full
   40-character commit SHA and matching trusted archive SHA-256. The lock
   persists that digest as `expectedSourceSha256`; a locked remote update reuses
   it only without a replacement source and refuses missing or mismatched proof.
2. Lexically validate the requested target and construct the complete
   destination graph, including `.beryl`, every selected managed file, root
   contracts, `.gitignore`, Git configuration, and the lockfile. The target
   must not be entered with `cd` and no directory may be created with `mkdir`
   until this validation completes. Each existing ancestor and each existing
   destination leaf is inspected without following symbolic links; any
   symbolic link is a hard failure.
3. Detect ownership and conflict policy for every planned mutation. A
   pre-existing `.beryl` without a valid ownership ledger is unowned and is
   refused by default. Explicit adoption inventories it, requires an identical
   staged managed surface, and records ownership without replacing unknown or
   target-owned content.
4. Stage the complete install surface and build one mutation ledger. The ledger
   records files, modes, root-contract decisions, `.gitignore` edits, the
   lockfile, and Git configuration together with their pre-operation state. It
   is lifecycle state and rollback evidence, not deletion authority: normal
   updates preserve deselected ambiguous paths and remove them from Beryl
   ownership. Declared target-owned and unknown content are preserved.
5. Apply staged changes and run only deterministic hooks whose mutations are
   represented in the same ledger. Build a candidate lock directly under
   `.beryl/` and verify installed readiness against that candidate before the
   atomic lock replacement. Failure at any point restores every ledgered
   mutation, including modes and Git configuration, and reports the failed
   phase and rollback result.
6. Atomically replace the lockfile last, then verify installed readiness again
   against the committed lock. The lock records selected components, immutable
   source identity and expected archive digest, ownership, retained backup
   identity, and persisted conflict-policy decisions.

Update defaults to the lockfile's immutable source identity, digest, and
component selection; normal updates preserve deselected ambiguous paths and
remove them from Beryl ownership. Restore applies a retained snapshot only after explicit
historical selection, explicit current selection before current-only removal,
current-source proof (with `--current-source-dir` when required), and matching
remote ref/digest validation before fetch. Uninstall requires explicit
`--profile`/`--components`, then removes only selected unchanged digest-proven
Beryl paths and restores recorded Git configuration. Adoption inventories an
unlocked installation, infers only an unambiguous minimal/standard/full surface
when no selection is supplied, and records only identical staged content. All
use the same no-follow validation and recovery discipline.

Bootstrap through an external coding agent is explicitly opt-in and runs only
after a successful lifecycle transaction. It is not a transaction hook:
external agent mutations cannot be completely enumerated or rolled back by
Beryl. Bootstrap failure therefore reports a separate post-transaction result
and must not leave the installation represented as an uncommitted transaction.

## Consequences

- **Benefit:** The target architecture gives direct installation and setup one
  inspectable, updateable lifecycle rather than separate mutation paths.
- **Benefit:** Initial installation and update share no-follow validation,
  rollback, and ownership safeguards.
- **Benefit:** The ledger makes root-contract, `.gitignore`, mode, lockfile,
  and Git-configuration changes recoverable rather than invisible side effects.
- **Benefit:** Bootstrap is honest about its separate failure and recovery
  boundary.
- **Tradeoff:** Adoption requires an exact staged-content match and refuses
  ambiguous unlocked `.beryl` content.
- **Tradeoff:** Lifecycle operations perform more preflight filesystem work
  before writing, and may reject ambiguous filesystems that earlier versions
  accepted.
- **Tradeoff:** Setup remains a user-experience frontend rather than an
  independent implementation path.
