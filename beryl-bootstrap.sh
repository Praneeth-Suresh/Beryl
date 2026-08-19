#!/bin/sh
set -eu

# This bootstrap is the trust root for automatic release selection. Obtain it
# through an independently trusted, versioned channel; do not treat a mutable
# raw URL as a trust root.
REPO_SLUG="Praneeth-Suresh/Beryl"
KEY_ID="beryl-release-rsa-20260819"
PUBLIC_KEY_SHA256="d405d4eb71087593e79dc8659e9d3a770b3a8dc5eda41d73e9840829aa640475"
METADATA_URL="https://github.com/${REPO_SLUG}/releases/latest/download/beryl-release-metadata-v1"
SIGNATURE_URL="${METADATA_URL}.sig"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [ -z "${TMP_DIR:-}" ] || rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

usage() {
  cat <<'USAGE'
Usage: sh beryl-bootstrap.sh [--release latest] [install.sh options]

Selects Beryl's current signed release, verifies its metadata signature and
archive SHA-256, then runs install.sh extracted from that verified archive.
The only supported automatic release selector is --release latest.
USAGE
}

require_command() { command -v "$1" >/dev/null 2>&1 || fail "signed release bootstrap requires $1"; }
ensure_https() { case "$1" in https://*) ;; *) fail "release downloads must use HTTPS: $1" ;; esac; }
fetch_https() {
  ensure_https "$1"
  curl --proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 3 -fsSL "$1" -o "$2"
}
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else fail 'signed release bootstrap requires sha256sum or shasum'; fi
}

RELEASE_SELECTOR="latest"
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --release) [ "$#" -ge 2 ] || fail '--release requires a value'; RELEASE_SELECTOR="$2"; shift 2 ;;
  --release=*) RELEASE_SELECTOR="${1#--release=}"; shift ;;
esac
[ "$RELEASE_SELECTOR" = latest ] || fail 'only --release latest is supported by the signed bootstrap'

for command_name in curl tar openssl date; do require_command "$command_name"; done
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-bootstrap.XXXXXX")" || fail 'could not create temporary directory'
KEY_FILE="$TMP_DIR/release-public.pem"
METADATA_FILE="$TMP_DIR/release-metadata"
SIGNATURE_FILE="$TMP_DIR/release-metadata.sig"
ARCHIVE_FILE="$TMP_DIR/beryl.tar.gz"
INSTALLER_FILE="$TMP_DIR/install.sh"

cat >"$KEY_FILE" <<'KEY'
-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA0pbwe6e+OzvwvISrJuQE
oBAEV8+tCOa4mMsvBZliAnpI2GNpF5ZbSc6unCNMazIKflTKvU8tmCPuvJeG2Iiq
klkLMUKiSYBD2H5Xq2ACV3vxEb3xMbxm+mSET/Tsg+7QOVPNNe5+4UqQAKDeSX39
lB4U8apVwuwxFThOA0NHUkQm6iv2tT2cFRfh5bXLt7tT54g2QMEEKsEDDKOW1pAd
yQUpEYOMERpcDdpMj20FFES81ZeeE5JrRqfCvYTsOwFbnrj9SBnPjwosMHBYpWaL
9Nn3iP/M4jcUAlRChLY88IRmK8zHI0V8kU6s+19xqw0cpHHwKi8nEwcZZmqUd9NP
MzhLgwhrYRwwidBpH14ZN6j5blYXtfNhAF1bykSWj89m6Zmi08VhEbnv0r0FK3Ff
YLJq2S3+Oblr4QdLZ8cMkrwsDHw1zslLx2UI11njMxhTm59awlMuz1B3Nfic2YOZ
Ng8U8UGJO6yXeyRt5+nKoe3nbAf3j1i1hdiqIYLqqin5AgMBAAE=
-----END PUBLIC KEY-----
KEY
actual_key_sha="$(openssl pkey -pubin -in "$KEY_FILE" -outform DER 2>/dev/null | sha256_of /dev/stdin)"
[ "$actual_key_sha" = "$PUBLIC_KEY_SHA256" ] || fail 'embedded release public key fingerprint mismatch'

printf 'beryl: fetching signed release metadata\n'
fetch_https "$METADATA_URL" "$METADATA_FILE" || fail 'could not fetch signed release metadata'
fetch_https "$SIGNATURE_URL" "$SIGNATURE_FILE" || fail 'could not fetch signed release metadata signature'
openssl dgst -sha256 -verify "$KEY_FILE" -signature "$SIGNATURE_FILE" "$METADATA_FILE" >/dev/null 2>&1 || fail 'release metadata signature verification failed'

schema=''
key_id=''
release_tag=''
source_ref=''
archive_sha256=''
issued_at=''
expires_at=''
while IFS='=' read -r field value; do
  [ -n "$field" ] || continue
  case "$field" in
    schemaVersion) [ -z "$schema" ] || fail 'duplicate metadata field: schemaVersion'; schema="$value" ;;
    keyId) [ -z "$key_id" ] || fail 'duplicate metadata field: keyId'; key_id="$value" ;;
    releaseTag) [ -z "$release_tag" ] || fail 'duplicate metadata field: releaseTag'; release_tag="$value" ;;
    sourceRef) [ -z "$source_ref" ] || fail 'duplicate metadata field: sourceRef'; source_ref="$value" ;;
    archiveSha256) [ -z "$archive_sha256" ] || fail 'duplicate metadata field: archiveSha256'; archive_sha256="$value" ;;
    issuedAt) [ -z "$issued_at" ] || fail 'duplicate metadata field: issuedAt'; issued_at="$value" ;;
    expiresAt) [ -z "$expires_at" ] || fail 'duplicate metadata field: expiresAt'; expires_at="$value" ;;
    *) fail "unknown metadata field: $field" ;;
  esac
done <"$METADATA_FILE"
[ "$schema" = 1 ] || fail 'unsupported release metadata schema'
[ "$key_id" = "$KEY_ID" ] || fail 'release metadata key ID is not trusted'
printf '%s\n' "$source_ref" | grep -Eq '^[0-9a-f]{40}$' || fail 'release metadata sourceRef must be a lowercase full commit SHA'
printf '%s\n' "$archive_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail 'release metadata archiveSha256 must be a lowercase SHA-256 digest'
printf '%s\n' "$issued_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || fail 'release metadata issuedAt is invalid'
printf '%s\n' "$expires_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || fail 'release metadata expiresAt is invalid'
now="$(LC_ALL=C TZ=UTC0 date '+%Y-%m-%dT%H:%M:%SZ')"
[ "$expires_at" ">" "$now" ] || fail 'release metadata has expired'
[ "$issued_at" "<" "$expires_at" ] || fail 'release metadata expiry must be after issue time'

archive_url="https://codeload.github.com/${REPO_SLUG}/tar.gz/${source_ref}"
printf 'beryl: selected signed release tag=%s ref=%s key=%s\n' "$release_tag" "$source_ref" "$key_id"
fetch_https "$archive_url" "$ARCHIVE_FILE" || fail 'could not fetch selected release archive'
actual_archive_sha="$(sha256_of "$ARCHIVE_FILE")"
[ "$actual_archive_sha" = "$archive_sha256" ] || fail 'signed release archive SHA-256 mismatch'
prefix="$(tar -tzf "$ARCHIVE_FILE" | sed -n '1s#/$##p; q')"
[ -n "$prefix" ] || fail 'selected release archive has no root directory'
tar -xOzf "$ARCHIVE_FILE" "$prefix/install.sh" >"$INSTALLER_FILE" 2>/dev/null || fail 'selected release archive lacks install.sh'
[ -s "$INSTALLER_FILE" ] || fail 'selected release install.sh is empty'
chmod 700 "$INSTALLER_FILE"
# Provenance is advisory lock audit data. The archive was verified above before
# these values are exported; lifecycle integrity continues to rely on the
# immutable ref and expected archive digest passed explicitly below.
export BERYL_SIGNED_RELEASE_TAG="$release_tag"
export BERYL_SIGNED_RELEASE_KEY_ID="$key_id"
export BERYL_SIGNED_RELEASE_ISSUED_AT="$issued_at"
export BERYL_SIGNED_RELEASE_EXPIRES_AT="$expires_at"
exec sh "$INSTALLER_FILE" --ref "$source_ref" --expected-sha256 "$archive_sha256" "$@"
