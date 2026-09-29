# Composing Modules

## Purpose

Select an existing package or module only after evidence establishes its exact
identity, reliability, compatibility, and fit. This skill prevents invented
names, typo-squatting, and unreviewed dependency growth; it does not install,
clone, or import anything by itself.

## Trigger

Use for requests to add a dependency, reuse a module, select a library, or
compose a feature from existing packages. Do not use it to guess a package name
from memory.

## Research protocol

1. Define the required public capability, runtime/language, license constraints,
   security requirements, and supported-version range.
2. Research at least three independent sources: the language's official package
   registry, the repository host/canonical repository, and one independent
   source such as package dependents, security advisory database, vendor docs,
   or a maintained ecosystem index. Record URLs and retrieval dates as facts.
3. Verify the exact registry package identity, publisher/owner where available,
   canonical repository URL, and release artifact. A name match alone is never
   evidence. Reject a mismatch, transfer ambiguity, lookalike, or unverifiable
   repository before any clone or install.
4. Compare at least two candidates, including the option of a small local
   implementation. Check API fit, transitive dependency cost, license,
   supported runtimes, maintenance, security advisories, and removal path.

## Hard reliability gate

A package is **reliable** only when all required facts and at least three
signals are satisfied:

Required facts:

- Registry identity and canonical repository identity match.
- The intended version has no unresolved critical advisory in an authoritative
  advisory source.
- Its license is compatible with the host project.

Signals (three required):

- at least 500 GitHub stars;
- at least 50 registry dependents, backlinks, or equivalent independently
  reported adopters;
- a stable release within the past 18 months;
- evidence of active maintenance (reviewed issues/commits/releases in 90 days);
- adoption or documentation from an independent authoritative maintainer.

Numbers are evidence thresholds, not a substitute for threat modelling. A
smaller package can be proposed as an exception, but must be labelled
`not-qualified` with the missing facts and needs explicit user approval.

## Decision record and adoption boundary

Present a compact evidence table with candidate, exact identity, sources,
required facts, signal count, version, license, security state, alternatives,
and recommendation. Preserve uncertainty rather than filling gaps with model
knowledge.

Stop after the recommendation. Request explicit approval that names the package
and version before running a package manager, cloning, changing a manifest or
lockfile, or importing the module. After approval, use the repository's normal
feature workflow, pin or constrain the approved version according to local
convention, add a smallest behavior test, and report dependency changes.
