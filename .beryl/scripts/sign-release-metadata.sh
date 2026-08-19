#!/usr/bin/env bash
set -euo pipefail

KEY_ID='beryl-release-rsa-20260819'
PUBLIC_KEY_SHA256='d405d4eb71087593e79dc8659e9d3a770b3a8dc5eda41d73e9840829aa640475'

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() {
  cat <<'USAGE'
Usage:
  sign-release-metadata.sh --release-tag TAG --source-ref FULL_SHA \
    --archive-sha256 SHA256 --expires-at RFC3339_UTC --private-key PATH --output-dir DIR

Writes canonical beryl-release-metadata-v1 and its detached RSA/SHA-256
signature. The private key must remain outside the repository.
USAGE
}

release_tag='' source_ref='' archive_sha256='' expires_at='' private_key='' output_dir=''
while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --release-tag) release_tag="${2:?--release-tag requires a value}"; shift 2 ;;
    --source-ref) source_ref="${2:?--source-ref requires a value}"; shift 2 ;;
    --archive-sha256) archive_sha256="${2:?--archive-sha256 requires a value}"; shift 2 ;;
    --expires-at) expires_at="${2:?--expires-at requires a value}"; shift 2 ;;
    --private-key) private_key="${2:?--private-key requires a value}"; shift 2 ;;
    --output-dir) output_dir="${2:?--output-dir requires a value}"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done
[[ -n "$release_tag" && -n "$source_ref" && -n "$archive_sha256" && -n "$expires_at" && -n "$private_key" && -n "$output_dir" ]] || { usage >&2; exit 1; }
[[ "$source_ref" =~ ^[0-9a-f]{40}$ ]] || fail '--source-ref must be a lowercase full 40-character commit SHA'
[[ "$archive_sha256" =~ ^[0-9a-f]{64}$ ]] || fail '--archive-sha256 must be a lowercase SHA-256 digest'
[[ "$expires_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || fail '--expires-at must be UTC RFC 3339'
[[ -f "$private_key" && ! -L "$private_key" ]] || fail '--private-key must be a regular file outside the repository'
command -v openssl >/dev/null 2>&1 || fail 'openssl is required for release signing'
private_abs="$(realpath "$private_key")"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ "$private_abs" != "$repo_root"/* ]] || fail 'private key must not be stored in the repository'
key_fingerprint="$(openssl pkey -in "$private_abs" -pubout -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
[[ "$key_fingerprint" == "$PUBLIC_KEY_SHA256" ]] || fail 'private key does not match the embedded release public key'
mkdir -p "$output_dir"
metadata="$output_dir/beryl-release-metadata-v1"
signature="$metadata.sig"
issued_at="$(LC_ALL=C TZ=UTC0 date '+%Y-%m-%dT%H:%M:%SZ')"
[[ "$issued_at" < "$expires_at" ]] || fail '--expires-at must be in the future'
umask 077
printf 'schemaVersion=1\nkeyId=%s\nreleaseTag=%s\nsourceRef=%s\narchiveSha256=%s\nissuedAt=%s\nexpiresAt=%s\n' \
  "$KEY_ID" "$release_tag" "$source_ref" "$archive_sha256" "$issued_at" "$expires_at" >"$metadata"
openssl dgst -sha256 -sign "$private_abs" -out "$signature" "$metadata"
chmod 644 "$metadata" "$signature"
printf 'Signed %s with %s; key=%s\n' "$metadata" "$signature" "$KEY_ID"
