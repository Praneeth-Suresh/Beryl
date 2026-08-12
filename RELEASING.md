# Releasing Beryl

## Publish A Trusted Remote-Install Checksum

1. Create and publish a GitHub Release whose target is the commit being
   released. The target may be selected through a tag, but the release workflow
   resolves it to a full 40-character commit SHA before publishing trust data.
2. The `Publish Release Checksum` workflow runs on `release.published`. It
   checks out that exact SHA, downloads GitHub's codeload archive for the exact
   SHA, computes SHA-256, and uploads:

   ```text
   beryl-<full-sha>.tar.gz.sha256
   ```

   The asset content is the standard `sha256sum` line for
   `beryl-<full-sha>.tar.gz`. The filename and checksum therefore identify the
   same immutable codeload archive that `install.sh` downloads.
3. Verify the asset is attached to the published release before recommending a
   remote install. If the automatic job must be rerun, use `workflow_dispatch`
   with the existing release tag; it resolves the release target again and
   overwrites only that checksum asset.

## Tell Users How To Discover Trust Data

Direct users to [GitHub Releases](https://github.com/Praneeth-Suresh/Beryl/releases),
or to the matching GitHub Releases API response. They must choose the asset
named `beryl-<full-sha>.tar.gz.sha256`, set `BERYL_REF` to that full SHA, and
set `BERYL_ARCHIVE_SHA256` to the digest in the asset. Do not publish a remote
installer command for a tag, branch, release page URL, or checksum whose full
SHA does not match the selected archive.

For the API route, maintainers and automation can inspect a release with:

```bash
gh release view <release-tag> --repo Praneeth-Suresh/Beryl --json assets,targetCommitish
```

Resolve `targetCommitish` to its full SHA, then select the asset whose filename
uses exactly that SHA. The release tag is discovery metadata only; it is never
an installer `--ref`.

## Release Verification

Before publishing, run:

```bash
./.beryl/scripts/run-lifecycle-tests.sh
./.beryl/scripts/check.sh --development
```

The release workflow intentionally has `contents: write` only because it must
upload the checksum asset; the normal deterministic-check workflow remains
read-only.
