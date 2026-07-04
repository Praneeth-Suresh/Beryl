# Task 01 — Modular, Git-History-Free Beryl Delivery with `.beryl/` Relocation

Formal plan produced under the `planning` skill. This is the planning gate: the plan is
presented for ratification. No relocation or installer code is implemented until the user
approves.

## Requested Outcome

Make Beryl plug-and-play into existing projects with minimum hindrance:

1. Users install without cloning the whole repository (git-history-free).
2. Users select only the components they need (e.g. agent framework without the driver).
3. All Beryl-owned files are relocated under a single `.beryl/` directory, and every internal
   pointer (scripts, configs, hooks, CI, docs, agent navigation paths) is updated so agents and
   tooling can still resolve every file.
4. A one-line remote installer, hosted at a raw GitHub URL, resolves component dependencies and
   fetches only the selected files.

## Bounded Context

Beryl is a control-plane repository. Component graph (verified against the repo):

| Component      | Canonical source (moves to`.beryl/`)                                    | Depends on     |
| -------------- | ------------------------------------------------------------------------- | -------------- |
| `agent-core` | `.beryl/agent/` (skills, adr, guides, templates, routing, rules)               | —             |
| `tool-shims` | `.beryl/agent/tool-instruction-template.md` + `sync-agent-env.sh`            | `agent-core` |
| `checks`     | `.beryl/scripts/`, `.beryl/agent/affected-tests.conf`, `.beryl/agent/test-manifest.conf` | `agent-core` |
| `githooks`   | `.beryl/githooks/`                                                             | `checks`     |
| `ci`         | `.github/workflows/deterministic-checks.yml`                            | `checks`     |
| `driver`     | `.beryl/driver/`                                                               | `agent-core` |

### Files that CANNOT move (external contract) — must stay at repo root and repoint into `.beryl/`

These are read by external tools at fixed locations. They are **generated** from
`.beryl/agent/tool-instruction-template.md`, so they stay at root but their generator writes them
to root while sourcing from `.beryl/`:

- `AGENTS.md`, `CLAUDE.md` (repo root)
- `.cursor/rules/agent-rules.md`
- `.github/copilot-instructions.md`
- `.codex/AGENTS.md`
- `.github/workflows/deterministic-checks.yml` (GitHub Actions requires `.github/workflows/`)
- `.gitignore` (root; entry changes `.beryl/agent/session-state.md` → `.beryl/agent/session-state.md`)

### Pointer surface (verified via grep)

- **Relative-root shell scripts** (`.beryl/scripts/*.sh` use `dirname/..`; `.beryl/agent/scripts/*.sh` use
  `dirname/../..`). If the whole tree moves as a unit into `.beryl/`, `ROOT_DIR` resolves to
  `.beryl/` and `${ROOT_DIR}/agent/...` references survive automatically. Two scripts need an
  explicit **repo-root** concept distinct from the new **beryl-root**:
  - `.beryl/agent/scripts/sync-agent-env.sh`: currently writes shims to `${ROOT_DIR}/AGENTS.md` etc.
    After the move `ROOT_DIR` = `.beryl/`, which is wrong. Must write shims to the repo root
    (`${BERYL_ROOT}/..`) while reading the template from `${BERYL_ROOT}/agent/`.
  - `.beryl/scripts/check-affected.sh`: uses `git -C "${ROOT_DIR}"`. Git must run at the repo root, not
    `.beryl/`. Needs `REPO_ROOT` for all git invocations.
- **Hardcoded string references** in configs and docs that grep found (not root-relative, so they
  need literal edits): `./.beryl/scripts/check.sh`, `.beryl/scripts/check-affected.sh`, `.beryl/agent/affected-tests.conf`,
  `.beryl/agent/test-manifest.conf`, `.beryl/agent/session-state.md`, `.beryl/agent/design-tree.md`, and the many
  `.beryl/agent/...` navigation pointers inside `.beryl/agent/tool-instruction-template.md`,
  `AGENTS.md`/`CLAUDE.md`/shims, `README.md`, `.beryl/scripts/README.md`, `.beryl/driver/README.md`,
  `.beryl/agent/task-routing.md`, `.beryl/agent/skills/*/SKILL.md`, `.beryl/agent/adr/*`, `Cheatsheet.md`, `Practise.md`.
- **Hook wiring**: `git config core.hooksPath` must become `.beryl/githooks`.
- **Test manifest scope**: `.beryl/agent/test-manifest.conf` `INCLUDE_GLOBS`/`MANIFEST_PATH` must be
  reviewed so the manifest still covers the relocated tree.

## Implementation Path

Relocate everything under `.beryl/` as one subtree, keep root shims generated.

Move `.beryl/agent/`, `.beryl/scripts/`, `.beryl/githooks/`, `.beryl/driver/` into `.beryl/`. Because the internal directory
layout is preserved as a unit, root-relative script resolution keeps working with minimal code
change. Root-level generated shims and CI stay put and repoint into `.beryl/`. The installer
payload becomes a single clean subtree, which makes git-history-free extraction trivial.

- Pros: smallest collision surface in host projects; installer extracts one subtree; most script
  references survive; matches the user's stated intent exactly.
- Cons: two scripts need a `REPO_ROOT` vs `BERYL_ROOT` split; every hardcoded doc/config pointer
  must be updated; hook path and CI must be repointed.

## Installer Design (git-history-free, raw GitHub URL)

- **Transport**: `curl -fsSL <raw-github-url>/install.sh | sh`. The script downloads a version-pinned
  tarball from `https://codeload.github.com/<owner>/Beryl/tar.gz/<tag>` and extracts only the
  `.beryl/<selected component paths>` entries via `tar -xz --strip-components=1`. No `.git`, no full
  clone. Because all canonical files live under `.beryl/`, extraction is a single subtree filter.
- **Component selection**:
  - `--profile minimal|standard|full`
  - `--components agent-core,driver` (dependencies auto-resolved from the manifest)
  - interactive multi-select when run with no flags
- **Manifest as single source of truth**: `.beryl/beryl.components.json` declares each component's
  paths, `requires`, and `postInstall` hooks. Both the remote `install.sh` and the existing
  `setup-project.sh` read it, so component logic is defined once.
- **Post-install**: run each selected component's hooks — notably `sync-agent-env.sh` to regenerate
  root shims, `update-test-manifest.sh` to seed the manifest, and optional `core.hooksPath` wiring.
- **Lifecycle**: write `.beryl/lock.json` (installed components + resolved version + source commit)
  so users can later `add`/`update`/`remove` components without re-fetching everything.

### Raw-GitHub-URL trust decision

A raw GitHub URL over HTTPS is acceptable and is the chosen host, with these mandatory safety
mitigations folded in (this addresses the `curl | sh` trust concern rather than switching hosts):

1. Version-pin the tarball to a tag/commit, never a moving branch.
2. Publish a SHA-256 checksum of `install.sh` in the README and print the pinned ref during install.
3. Document an inspect-before-run path (`curl -fsSL <url> -o install.sh; less install.sh; sh install.sh`).
4. HTTPS only; refuse to run if the download is not over TLS.
5. The installer never executes fetched project code beyond the declared, in-repo `postInstall`
   hooks, and prints each hook before running it.

## Acceptance Criteria

- **Source-level check**: `.beryl/agent/`, `.beryl/scripts/`, `.beryl/githooks/`, `.beryl/driver/` no longer exist at repo root;
  they exist under `.beryl/`. `rg -n "(^|[^.])\b(agent|scripts|githooks|driver)/" ` finds no stale
  root-relative Beryl pointer outside `.beryl/` except the intentional root shims/CI that reference
  `.beryl/...`. `.beryl/beryl.components.json` and installer exist.
- **Generated-output check**: running `.beryl/agent/scripts/sync-agent-env.sh` regenerates
  `AGENTS.md`, `CLAUDE.md`, `.cursor/rules/agent-rules.md`, `.github/copilot-instructions.md`,
  `.codex/AGENTS.md` at the repo root, each pointing at `.beryl/agent/...` paths.
- **Installer check**: in a scratch temp project,
  `sh install.sh --components agent-core,driver` produces `.beryl/agent/` and `.beryl/driver/`,
  no `.beryl/scripts/` or `.beryl/githooks/`, and a `.beryl/lock.json` listing the resolved set.
  A second run with `--profile standard` adds `checks` + `githooks` idempotently.
- **Test/check command**:
  - Narrow: `./.beryl/scripts/check-md.sh` and `./.beryl/agent/scripts/agent-doctor.sh`
  - Broader: `./.beryl/scripts/check.sh` (runs md, tests-unchanged, project/affected gate) passes
    from a relocated layout.
  - Installer: dry-run extraction into a temp dir asserts only selected paths are present.
- **User-visible behavior**: a user in an existing repo runs one `curl | sh` line, picks components,
  and ends up with a working `.beryl/` control plane plus regenerated root instruction shims —
  without cloning Beryl.

(No browser/Playwright check: this task has no web UI surface.)

## Commit Boundaries

- **Commit 1 — Component manifest (no move yet)**: add `beryl.components.json` describing current
  layout + profiles. Purpose: single source of truth. Validate: `./.beryl/scripts/check-md.sh` + a manifest
  schema/lint check.
- **Commit 2 — Relocate tree to `.beryl/` + fix script roots**: `git mv` of `.beryl/agent/`, `.beryl/scripts/`,
  `.beryl/githooks/`, `.beryl/driver/` under `.beryl/`; add `REPO_ROOT`/`BERYL_ROOT` split in
  `sync-agent-env.sh` and `check-affected.sh`; update manifest paths. Validate:
  `./.beryl/scripts/check.sh`.
- **Commit 3 — Repoint generated shims + CI + hooks + gitignore**: regenerate root shims to source
  from `.beryl/`; update `.github/workflows/deterministic-checks.yml` to call `.beryl/scripts/check.sh`;
  update `core.hooksPath` docs to `.beryl/githooks`; update `.gitignore` entry. Validate:
  `sync-agent-env.sh` output + CI workflow lint + hook dry-run.
- **Commit 4 — Repoint documentation pointers**: `README.md`, `.beryl/scripts/README.md`, `.beryl/driver/README.md`,
  `.beryl/agent/*` docs, `.beryl/agent/skills/*`, `.beryl/agent/adr/*`, `Cheatsheet.md`, `Practise.md`. Validate:
  `./.beryl/scripts/check-md.sh` + grep shows no stale pointers.
- **Commit 5 — Remote installer + lockfile**: add `install.sh` (tarball transport, component/profile
  selection, dependency resolution, postInstall, `.beryl/lock.json`) and refactor `setup-project.sh`
  to consume the manifest. Validate: temp-project install matrix (minimal/standard/full + explicit
  component sets) + checksum/inspect-before-run docs.
- **Commit 6 — ADR + docs for the delivery model**: new ADR for `.beryl/` relocation and
  git-history-free modular install; update README Quick Start. Validate: `./.beryl/scripts/check-md.sh`.

## Risks

- **Scope risk**: pointer updates span ~53 files (many are docs). Mitigation: automated grep gate in
  acceptance criteria; treat docs as one dedicated commit; do not touch unrelated content.
- **Architecture risk**: introducing `REPO_ROOT` vs `BERYL_ROOT` could leak the split across scripts.
  Mitigation: define both once in a tiny shared helper (`.beryl/scripts/paths.sh` or existing
  `test-manifest-lib.sh` style) and source it; keep the boundary explicit. Risk that generated shims
  at root and CI drift from the `.beryl/` source — mitigated by keeping `sync-agent-env.sh` the sole
  generator and adding it to `agent-doctor.sh` verification.
- **UX risk**: `curl | sh` trust. Mitigated by version pinning, published checksum, inspect-before-run
  path, and printing every hook before execution. Second risk: installing into a repo with existing
  `.beryl/agent/`/`.beryl/scripts/` names — mitigated because everything now nests under `.beryl/`, shrinking
  collisions to the unavoidable root shims, for which the conflict policy is skip/overwrite/merge
  with no silent clobber.

## Tests / Checks To Run

- `./.beryl/scripts/check.sh` (md, test-immutability, affected-test gate) from relocated layout.
- `./.beryl/agent/scripts/agent-doctor.sh` and `module-doctor.sh` to verify path integrity.
- `sync-agent-env.sh` regeneration diff review (shims land at root, source from `.beryl/`).
- Installer matrix in throwaway temp dirs: `minimal`, `standard`, `full`, and explicit
  `--components` sets; assert only-selected extraction, dependency resolution, idempotent re-run,
  and lockfile contents. Clean up temp dirs after.

## Design Files / ADRs Likely To Change

- New ADR: `.beryl/agent/adr/0004-relocate-control-plane-under-dot-beryl.md`.
- New ADR: `.beryl/agent/adr/0005-git-history-free-modular-installer.md`.
- Update `.beryl/agent/architecture.md` and `.beryl/agent/design-tree.md` for the `.beryl/` layout + manifest.
- Update `.beryl/agent/README.md`, `.beryl/scripts/README.md`, `.beryl/driver/README.md`, root `README.md`.
- Possibly extend `.beryl/agent/ubiquitous-language.md` with terms: component, profile, manifest, lockfile,
  beryl-root vs repo-root.

## Open Questions / Assumptions

1. **Assumption**: tool instruction shims (`AGENTS.md`, `CLAUDE.md`, `.cursor`, `.codex`,
   `.github/copilot-instructions.md`) must remain at their tool-mandated root locations and cannot
   move under `.beryl/`. Confirm no tool is configured to read them from elsewhere.
2. **Open**: distribution channels beyond raw `curl | sh` — do you also want an `npx beryl-init`
   wrapper now, or defer until the shell installer is proven?
3. **Open**: should `.beryl/lock.json` be committed by host projects (reproducible installs) or
   gitignored? Recommendation: commit it.
4. **Open**: minimum supported environment for the installer — POSIX `sh` + `curl` + `tar` only, or
   may it assume `bash`? Recommendation: POSIX `sh` + `curl` + `tar` for maximum reach.

## Stop Condition

Planning gate. Awaiting user ratification before implementing any relocation, pointer update, or
installer code.
