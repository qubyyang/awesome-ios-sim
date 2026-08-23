#!/bin/bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly NATIVE_ASSETS_DIRECTORY="${AISS_NATIVE_ASSETS_DIR:-${PROJECT_ROOT}/.build/release-artifacts}"
readonly OUTPUT_DIRECTORY="${AISS_DIST_DIR:-${PROJECT_ROOT}/.build/release-artifacts}"
readonly SIGNING_IDENTITY="${AISS_CODESIGN_IDENTITY:-}"
readonly REQUIRE_SIGNING="${AISS_REQUIRE_SIGNING:-false}"

fail() {
    printf '[build-universal-artifact] ERROR: %s\n' "$*" >&2
    exit 1
}

case "$REQUIRE_SIGNING" in
    true | false) ;;
    *) fail "AISS_REQUIRE_SIGNING must be true or false" ;;
esac

for command in codesign ditto jq lipo shasum tar; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

cd "$PROJECT_ROOT"
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
    VERSION="$(Scripts/release/verify-version.sh "${GITHUB_REF_NAME:-}")"
else
    VERSION="$(Scripts/release/verify-version.sh)"
fi

if [[ "$REQUIRE_SIGNING" == "true" && -z "$SIGNING_IDENTITY" ]]; then
    fail "Developer ID signing is required but AISS_CODESIGN_IDENTITY is empty"
fi
if [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
    fail "Signing identity must be a Developer ID Application identity"
fi

mkdir -p "$OUTPUT_DIRECTORY"
STAGING_ROOT="$(mktemp -d "$OUTPUT_DIRECTORY/.universal.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT INT TERM

PACKAGE_NAME="awesome-ios-sim-${VERSION}-macos-universal"
PACKAGE_ROOT="$STAGING_ROOT/$PACKAGE_NAME"
mkdir -p "$PACKAGE_ROOT/bin"

for architecture in arm64 x86_64; do
    archive="$NATIVE_ASSETS_DIRECTORY/awesome-ios-sim-${VERSION}-macos-${architecture}.tar.gz"
    checksum="$archive.sha256"
    [[ -f "$archive" ]] || fail "Missing native archive: $archive"
    [[ -f "$checksum" ]] || fail "Missing native checksum: $checksum"
    (
        cd "$NATIVE_ASSETS_DIRECTORY"
        shasum -a 256 -c "$(basename "$checksum")"
    )
    mkdir -p "$STAGING_ROOT/$architecture"
    tar -xzf "$archive" -C "$STAGING_ROOT/$architecture"

    native_root="$STAGING_ROOT/$architecture/awesome-ios-sim-${VERSION}-macos-${architecture}"
    metadata="$native_root/RELEASE-METADATA.json"
    [[ -f "$metadata" ]] || fail "Native archive is missing RELEASE-METADATA.json: $architecture"
    jq -e \
        --arg version "$VERSION" \
        --arg architecture "$architecture" \
        '.version == $version and .architecture == $architecture and .sourceDirty == false' \
        "$metadata" >/dev/null || fail "Native metadata contract failed: $architecture"
    for executable in ios-sim-state ios-sim-state-mcp; do
        [[ "$(lipo -archs "$native_root/bin/$executable")" == "$architecture" ]] || \
            fail "$executable is not a native $architecture binary"
    done
done

ARM_ROOT="$STAGING_ROOT/arm64/awesome-ios-sim-${VERSION}-macos-arm64"
INTEL_ROOT="$STAGING_ROOT/x86_64/awesome-ios-sim-${VERSION}-macos-x86_64"
ARM_REVISION="$(jq -r '.sourceRevision' "$ARM_ROOT/RELEASE-METADATA.json")"
INTEL_REVISION="$(jq -r '.sourceRevision' "$INTEL_ROOT/RELEASE-METADATA.json")"
[[ "$ARM_REVISION" == "$INTEL_REVISION" ]] || fail "Native archives come from different revisions"
if [[ -n "${GITHUB_SHA:-}" && "$ARM_REVISION" != "$GITHUB_SHA" ]]; then
    fail "Native archives do not match GITHUB_SHA"
fi

for resource in LICENSE README.md README.zh-CN.md; do
    cmp "$ARM_ROOT/$resource" "$INTEL_ROOT/$resource" >/dev/null || \
        fail "$resource differs between native archives"
    install -m 0644 "$ARM_ROOT/$resource" "$PACKAGE_ROOT/$resource"
done

for executable in ios-sim-state ios-sim-state-mcp; do
    lipo -create \
        "$ARM_ROOT/bin/$executable" \
        "$INTEL_ROOT/bin/$executable" \
        -output "$PACKAGE_ROOT/bin/$executable"
    chmod 0755 "$PACKAGE_ROOT/bin/$executable"
    architectures=" $(lipo -archs "$PACKAGE_ROOT/bin/$executable") "
    [[ "$architectures" == *" arm64 "* && "$architectures" == *" x86_64 "* ]] || \
        fail "$executable is not a universal arm64/x86_64 binary"
done

[[ "$("$PACKAGE_ROOT/bin/ios-sim-state" --version)" == "$VERSION" ]] || \
    fail "Universal CLI version does not match $VERSION"
[[ "$("$PACKAGE_ROOT/bin/ios-sim-state-mcp" --version)" == "$VERSION" ]] || \
    fail "Universal MCP version does not match $VERSION"

SIGNED=false
TEAM_IDENTIFIER=""
if [[ -n "$SIGNING_IDENTITY" ]]; then
    printf '[build-universal-artifact] Signing universal executables with Developer ID\n'
    for executable in ios-sim-state ios-sim-state-mcp; do
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
            "$PACKAGE_ROOT/bin/$executable"
        codesign --verify --strict --verbose=2 "$PACKAGE_ROOT/bin/$executable"
    done
    TEAM_IDENTIFIER="$(
        codesign -d --verbose=4 "$PACKAGE_ROOT/bin/ios-sim-state" 2>&1 \
            | sed -n 's/^TeamIdentifier=//p'
    )"
    [[ -n "$TEAM_IDENTIFIER" && "$TEAM_IDENTIFIER" != "not set" ]] || \
        fail "Signed executable does not contain a TeamIdentifier"
    SIGNED=true
elif [[ "$REQUIRE_SIGNING" == "false" ]]; then
    printf '[build-universal-artifact] Building unsigned release candidate\n'
fi

jq -n \
    --arg version "$VERSION" \
    --arg sourceRevision "$ARM_REVISION" \
    --argjson signed "$SIGNED" \
    --arg signingIdentity "$SIGNING_IDENTITY" \
    --arg teamIdentifier "$TEAM_IDENTIFIER" \
    --arg schemaVersion "awesome-ios-sim/v1alpha1" \
    --arg minimumMacOS "13.0" \
    '{
        name: "awesome-ios-sim",
        version: $version,
        platform: "macOS",
        architecture: "universal",
        architectures: ["arm64", "x86_64"],
        minimumMacOS: $minimumMacOS,
        sourceRevision: $sourceRevision,
        sourceDirty: false,
        profileSchema: $schemaVersion,
        executables: ["bin/ios-sim-state", "bin/ios-sim-state-mcp"],
        signing: (if $signed then {
            status: "developer-id",
            identity: $signingIdentity,
            teamIdentifier: $teamIdentifier,
            hardenedRuntime: true,
            secureTimestamp: true
        } else {
            status: "unsigned-release-candidate"
        } end)
    }' > "$PACKAGE_ROOT/RELEASE-METADATA.json"

ARCHIVE="$OUTPUT_DIRECTORY/${PACKAGE_NAME}.zip"
CHECKSUM="$ARCHIVE.sha256"
rm -f "$ARCHIVE" "$CHECKSUM"
COPYFILE_DISABLE=1 ditto -c -k --keepParent "$PACKAGE_ROOT" "$ARCHIVE"
(
    cd "$OUTPUT_DIRECTORY"
    shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

printf '[build-universal-artifact] Created %s\n' "$ARCHIVE"
printf '[build-universal-artifact] Created %s\n' "$CHECKSUM"
