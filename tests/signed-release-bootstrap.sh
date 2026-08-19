#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/beryl-signed-bootstrap.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect_failure() { local output="$1"; shift; if "$@" >"$output" 2>&1; then fail "command unexpectedly succeeded: $*"; fi; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 missing: $2"; }

private_key="${TMP_DIR}/test-private.pem"
public_key="${TMP_DIR}/test-public.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$private_key" >/dev/null 2>&1
openssl pkey -in "$private_key" -pubout -out "$public_key"
key_fingerprint="$(openssl pkey -pubin -in "$public_key" -outform DER | sha256sum | awk '{print $1}')"

bootstrap="${TMP_DIR}/beryl-bootstrap.sh"
cp "$REPO_ROOT/beryl-bootstrap.sh" "$bootstrap"
python3 - "$bootstrap" "$public_key" "$key_fingerprint" <<'PY'
from pathlib import Path
import re, sys
script = Path(sys.argv[1])
public = Path(sys.argv[2])
fingerprint = sys.argv[3]
text = script.read_text()
pem = public.read_text().rstrip()
text = re.sub(r"PUBLIC_KEY_SHA256=\"[0-9a-f]+\"", f'PUBLIC_KEY_SHA256="{fingerprint}"', text)
text = re.sub(r"-----BEGIN PUBLIC KEY-----\n.*?-----END PUBLIC KEY-----", pem, text, count=1, flags=re.S)
script.write_text(text)
PY
chmod +x "$bootstrap"

candidate_dir="${TMP_DIR}/candidate"
mkdir "$candidate_dir"
tar -C "$REPO_ROOT" --exclude=.git -czf "${TMP_DIR}/release.tar.gz" .
# The bootstrap expects a single archive root directory. Repackage with one.
mkdir "${candidate_dir}/beryl-release"
tar -C "$REPO_ROOT" --exclude=.git -cf - . | tar -C "${candidate_dir}/beryl-release" -xf -
tar -C "$candidate_dir" -czf "${TMP_DIR}/release-rooted.tar.gz" beryl-release
archive="${TMP_DIR}/release-rooted.tar.gz"
digest="$(sha256sum "$archive" | awk '{print $1}')"
metadata="${TMP_DIR}/beryl-release-metadata-v1"
printf 'schemaVersion=1\nkeyId=beryl-release-rsa-20260819\nreleaseTag=v-test\nsourceRef=0123456789abcdef0123456789abcdef01234567\narchiveSha256=%s\nissuedAt=2026-01-01T00:00:00Z\nexpiresAt=2099-01-01T00:00:00Z\n' "$digest" >"$metadata"
openssl dgst -sha256 -sign "$private_key" -out "${metadata}.sig" "$metadata"

bin="${TMP_DIR}/bin"
mkdir "$bin"
cat >"${bin}/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out='' url=''
while (($#)); do
  case "$1" in -o) out="$2"; shift 2 ;; *) url="$1"; shift ;; esac
done
case "$url" in
  *beryl-release-metadata-v1.sig) cp "${TEST_METADATA}.sig" "$out" ;;
  *beryl-release-metadata-v1) cp "$TEST_METADATA" "$out" ;;
  *codeload.github.com*) cp "$TEST_ARCHIVE" "$out" ;;
  *) printf 'unexpected URL: %s\n' "$url" >&2; exit 23 ;;
esac
CURL
chmod +x "${bin}/curl"

target="${TMP_DIR}/target"
env PATH="${bin}:$PATH" TEST_METADATA="$metadata" TEST_ARCHIVE="$archive" \
  sh "$bootstrap" --release latest --target "$target" --profile minimal
assert_contains "${target}/.beryl/lock.json" '"sourceRef": "0123456789abcdef0123456789abcdef01234567"'
assert_contains "${target}/.beryl/lock.json" "\"expectedSourceSha256\": \"${digest}\""
assert_contains "${target}/.beryl/lock.json" '"releaseTrust": "signed-bootstrap"'
assert_contains "${target}/.beryl/lock.json" '"signedReleaseKeyId": "beryl-release-rsa-20260819"'

# Metadata tampering is rejected before archive fetch or target creation.
printf 'tampered=true\n' >>"$metadata"
tampered_target="${TMP_DIR}/tampered-target"
expect_failure "${TMP_DIR}/tampered.out" env PATH="${bin}:$PATH" TEST_METADATA="$metadata" TEST_ARCHIVE="$archive" \
  sh "$bootstrap" --release latest --target "$tampered_target" --profile minimal
assert_contains "${TMP_DIR}/tampered.out" 'release metadata signature verification failed'
[[ ! -e "$tampered_target" ]] || fail 'tampered metadata created a target'

printf 'signed release bootstrap tests passed\n'
