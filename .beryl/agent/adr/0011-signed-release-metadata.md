# ADR 0011: Signed Release Metadata With an Independent Bootstrap Trust Root

## Status

Accepted

## Context

A full commit SHA plus archive checksum proves byte integrity only after a user
obtains both values through a trusted channel. It does not let Beryl safely
automate release discovery.

## Decision

A versioned `beryl-bootstrap.sh`, obtained through an independently trusted
bootstrap channel, embeds Beryl's RSA release public key. It fetches fixed
HTTPS metadata and detached signature assets, verifies the signature with
OpenSSL, rejects malformed or expired metadata, derives the codeload archive
URL from a signed immutable SHA, verifies the signed archive digest, and
executes `install.sh` only after extracting it from that verified archive.

The signing private key remains outside the repository and GitHub Actions.
`.beryl/scripts/sign-release-metadata.sh` is a maintainer workstation helper;
it refuses repository-resident or non-matching keys. A metadata document cannot
introduce a replacement root key. Rotation requires a new independently trusted
bootstrap release.

Pinned `install.sh --ref <sha> --expected-sha256 <digest>` remains available for
recovery and audit policy. Existing locked updates remain pinned unless the
user explicitly invokes the signed bootstrap selection path.

## Consequences

- Users no longer type a SHA/digest for the normal signed-release path.
- First bootstrap acquisition remains an explicit trust decision.
- Signature and expiry verification fail before target mutation.
- Releases require a protected offline signing step and cannot rely solely on
  GitHub asset-write permission.
