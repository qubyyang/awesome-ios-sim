#!/bin/bash

set -euo pipefail

readonly ARCHIVE="${1:-}"
readonly NOTARY_KEY_PATH="${AISS_NOTARY_KEY_PATH:-}"
readonly NOTARY_KEY_ID="${AISS_NOTARY_KEY_ID:-}"
readonly NOTARY_ISSUER_ID="${AISS_NOTARY_ISSUER_ID:-}"

fail() {
    printf '[notarize-artifact] ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -n "$ARCHIVE" ]] || fail "Usage: notarize-artifact.sh <universal-archive.zip>"
[[ -f "$ARCHIVE" ]] || fail "Archive does not exist: $ARCHIVE"
[[ "$ARCHIVE" == *.zip ]] || fail "Apple notarization input must be a ZIP archive"
[[ -f "$NOTARY_KEY_PATH" ]] || fail "AISS_NOTARY_KEY_PATH must reference an App Store Connect API key"
[[ -n "$NOTARY_KEY_ID" ]] || fail "AISS_NOTARY_KEY_ID is required"
[[ -n "$NOTARY_ISSUER_ID" ]] || fail "AISS_NOTARY_ISSUER_ID is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"
command -v xcrun >/dev/null 2>&1 || fail "xcrun is required"

OUTPUT="${AISS_NOTARIZATION_RESULT:-${ARCHIVE}.notarization.json}"
TEMPORARY_RESULT="$(mktemp "${TMPDIR:-/tmp}/awesome-ios-sim-notary.XXXXXX")"
cleanup() {
    rm -f "$TEMPORARY_RESULT"
}
trap cleanup EXIT INT TERM

printf '[notarize-artifact] Submitting %s to Apple notary service\n' "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait \
    --output-format json > "$TEMPORARY_RESULT"

STATUS="$(jq -r '.status // empty' "$TEMPORARY_RESULT")"
[[ "$STATUS" == "Accepted" ]] || {
    jq . "$TEMPORARY_RESULT" >&2
    fail "Apple notary service did not accept the archive"
}

ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
jq \
    --arg archive "$(basename "$ARCHIVE")" \
    --arg sha256 "$ARCHIVE_SHA256" \
    '{archive: $archive, sha256: $sha256, submission: .}' \
    "$TEMPORARY_RESULT" > "$OUTPUT"

printf '[notarize-artifact] Accepted; result written to %s\n' "$OUTPUT"
