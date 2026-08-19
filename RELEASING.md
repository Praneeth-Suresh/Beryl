# Releasing Beryl

## Release Trust Model

Beryl automatic release selection has two trust layers:

1. A **versioned, independently trusted** `beryl-bootstrap.sh` embeds Beryl's
   release-signing public key and verifies signed release metadata.
2. A designated maintainer signs that metadata with the corresponding private
   key, which remains outside this repository and GitHub Actions.

Do not describe a mutable raw installer URL or a GitHub `latest` redirect by
itself as a trust root. GitHub distributes the metadata assets, but the
bootstrap accepts them only after cryptographic signature verification.

## Publish A Signed Release

1. Create and publish a GitHub Release whose target is the intended commit.
   The `Publish Release Checksum` workflow resolves that target to a full
   40-character SHA, downloads its codeload archive, and uploads
   `beryl-<full-sha>.tar.gz.sha256`.
2. Obtain the digest from that uploaded checksum asset and sign canonical
   metadata from a secured maintainer workstation. The private key must be the
   externally stored key whose public SHA-256 fingerprint is:

   ```text
   d405d4eb71087593e79dc8659e9d3a770b3a8dc5eda41d73e9840829aa640475
   ```

   For example, issue metadata for 30 days:

   ```bash
   RELEASE_SHA='<full-40-character-release-sha>'
   ARCHIVE_SHA256='<digest-from-beryl-<sha>.tar.gz.sha256>'
   ./\.beryl/scripts/sign-release-metadata.sh \
     --release-tag vX.Y.Z \
     --source-ref "$RELEASE_SHA" \
     --archive-sha256 "$ARCHIVE_SHA256" \
     --expires-at 2026-09-18T00:00:00Z \
     --private-key "$HOME/.config/beryl/release-signing-key.pem" \
     --output-dir /tmp/beryl-release-assets
   ```

   The helper refuses a private key stored in the repository or one that does
   not match Beryl's embedded public key. Do not pass a private-key path to CI,
   put the key in a GitHub secret, commit it, or paste it into issue/PR text.
3. Inspect and upload both generated assets to the same GitHub Release:

   ```bash
   gh release upload vX.Y.Z \
     /tmp/beryl-release-assets/beryl-release-metadata-v1 \
     /tmp/beryl-release-assets/beryl-release-metadata-v1.sig \
     --repo Praneeth-Suresh/Beryl
   ```

   The release is not eligible for automatic installation until the checksum,
   metadata, and signature assets are all present.
4. Verify from a clean directory using the versioned bootstrap obtained from
   Beryl's independently trusted bootstrap channel:

   ```bash
   sh beryl-bootstrap.sh --release latest --dry-run
   ```

## Key Custody, Rotation, And Incidents

- The private key is an offline/protected maintainer credential. Keep it at
  owner-only permissions, back it up through the organization's approved secret
  recovery process, and never store it in this repository.
- Key rotation requires a new bootstrap version containing the new public key,
  distributed through the independently trusted bootstrap channel. Metadata
  cannot authorize a new root key by itself.
- If the private key may be compromised, stop publishing signed metadata,
  revoke the bootstrap channel, generate a replacement key, publish a newly
  authenticated bootstrap, and publish only replacement metadata signed by the
  new key. Treat previously signed `latest` metadata as untrusted.

## Release Verification

Before publishing, run:

```bash
./.beryl/scripts/run-lifecycle-tests.sh
./.beryl/scripts/check.sh --development
```

The checksum workflow intentionally has `contents: write` only because it must
upload a release asset. It never receives the release-signing private key.
