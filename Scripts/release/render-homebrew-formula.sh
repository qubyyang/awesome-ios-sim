#!/bin/bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly ARCHIVE="${1:-}"
readonly OUTPUT="${2:-${PROJECT_ROOT}/.build/release-artifacts/awesome-ios-sim.rb}"
readonly TEMPLATE="$PROJECT_ROOT/Scripts/release/templates/awesome-ios-sim.rb.in"

fail() {
    printf '[render-homebrew-formula] ERROR: %s\n' "$*" >&2
    exit 1
}

[[ -f "$ARCHIVE" ]] || fail "Usage: render-homebrew-formula.sh <universal-archive.zip> [output.rb]"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"

cd "$PROJECT_ROOT"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    VERSION="$(Scripts/release/verify-version.sh "${GITHUB_REF_NAME:-}")"
else
    VERSION="$(Scripts/release/verify-version.sh)"
fi

EXPECTED_ARCHIVE="awesome-ios-sim-${VERSION}-macos-universal.zip"
[[ "$(basename "$ARCHIVE")" == "$EXPECTED_ARCHIVE" ]] || \
    fail "Expected archive name $EXPECTED_ARCHIVE"
SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
mkdir -p "$(dirname "$OUTPUT")"
sed \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@SHA256@|$SHA256|g" \
    "$TEMPLATE" > "$OUTPUT"
ruby -c "$OUTPUT" >/dev/null

printf '[render-homebrew-formula] Created %s\n' "$OUTPUT"
