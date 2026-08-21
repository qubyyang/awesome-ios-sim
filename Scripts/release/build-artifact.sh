#!/bin/bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly OUTPUT_DIRECTORY="${AISS_DIST_DIR:-${PROJECT_ROOT}/.build/release-artifacts}"

fail() {
    printf '[build-artifact] ERROR: %s\n' "$*" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v lipo >/dev/null 2>&1 || fail "lipo is required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"

cd "$PROJECT_ROOT"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    VERSION="$(Scripts/release/verify-version.sh "${GITHUB_REF_NAME:-}")"
else
    VERSION="$(Scripts/release/verify-version.sh)"
fi
ARCHITECTURE="$(uname -m)"
case "$ARCHITECTURE" in
    arm64 | x86_64) ;;
    *) fail "Unsupported release architecture: ${ARCHITECTURE}" ;;
esac

mkdir -p "$OUTPUT_DIRECTORY"
STAGING_ROOT="$(mktemp -d "$OUTPUT_DIRECTORY/.stage.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT INT TERM

PACKAGE_NAME="awesome-ios-sim-${VERSION}-macos-${ARCHITECTURE}"
PACKAGE_ROOT="$STAGING_ROOT/$PACKAGE_NAME"
mkdir -p "$PACKAGE_ROOT/bin"

printf '[build-artifact] Building %s for %s\n' "$VERSION" "$ARCHITECTURE"
swift build -c release
BIN_DIRECTORY="$(swift build -c release --show-bin-path)"

install -m 0755 "$BIN_DIRECTORY/ios-sim-state" "$PACKAGE_ROOT/bin/ios-sim-state"
install -m 0755 "$BIN_DIRECTORY/ios-sim-state-mcp" "$PACKAGE_ROOT/bin/ios-sim-state-mcp"
install -m 0644 LICENSE "$PACKAGE_ROOT/LICENSE"
install -m 0644 README.md "$PACKAGE_ROOT/README.md"
install -m 0644 README.zh-CN.md "$PACKAGE_ROOT/README.zh-CN.md"

[[ "$("$PACKAGE_ROOT/bin/ios-sim-state" --version)" == "$VERSION" ]] || \
    fail "CLI version does not match ${VERSION}"
[[ "$("$PACKAGE_ROOT/bin/ios-sim-state-mcp" --version)" == "$VERSION" ]] || \
    fail "MCP version does not match ${VERSION}"

for executable in "$PACKAGE_ROOT/bin/ios-sim-state" "$PACKAGE_ROOT/bin/ios-sim-state-mcp"; do
    [[ "$(lipo -archs "$executable")" == "$ARCHITECTURE" ]] || \
        fail "$(basename "$executable") is not a ${ARCHITECTURE} binary"
done

SOURCE_REVISION="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || printf 'unknown')}"
SOURCE_DIRTY=false
if [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    SOURCE_DIRTY=true
fi
jq -n \
    --arg version "$VERSION" \
    --arg architecture "$ARCHITECTURE" \
    --arg sourceRevision "$SOURCE_REVISION" \
    --argjson sourceDirty "$SOURCE_DIRTY" \
    --arg schemaVersion "awesome-ios-sim/v1alpha1" \
    --arg minimumMacOS "13.0" \
    '{
        name: "awesome-ios-sim",
        version: $version,
        platform: "macOS",
        architecture: $architecture,
        minimumMacOS: $minimumMacOS,
        sourceRevision: $sourceRevision,
        sourceDirty: $sourceDirty,
        profileSchema: $schemaVersion,
        executables: ["bin/ios-sim-state", "bin/ios-sim-state-mcp"]
    }' > "$PACKAGE_ROOT/RELEASE-METADATA.json"

ARCHIVE="$OUTPUT_DIRECTORY/${PACKAGE_NAME}.tar.gz"
CHECKSUM="$ARCHIVE.sha256"
rm -f "$ARCHIVE" "$CHECKSUM"
COPYFILE_DISABLE=1 tar -C "$STAGING_ROOT" -czf "$ARCHIVE" "$PACKAGE_NAME"
(
    cd "$OUTPUT_DIRECTORY"
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

printf '[build-artifact] Created %s\n' "$ARCHIVE"
printf '[build-artifact] Created %s\n' "$CHECKSUM"
