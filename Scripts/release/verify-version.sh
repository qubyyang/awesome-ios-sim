#!/bin/bash

set -euo pipefail

readonly PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
readonly TAG="${1:-}"

fail() {
    printf '[verify-version] ERROR: %s\n' "$*" >&2
    exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

SWIFT_VERSION="$(
    sed -n 's/.*public static let version = "\([^"]*\)".*/\1/p' \
        "$PROJECT_ROOT/Sources/SimulatorStateCore/Version.swift"
)"
PACKAGE_VERSION="$(jq -r '.version' "$PROJECT_ROOT/package.json")"
LOCKFILE_VERSION="$(jq -r '.version' "$PROJECT_ROOT/package-lock.json")"
LOCKFILE_ROOT_VERSION="$(jq -r '.packages[""].version' "$PROJECT_ROOT/package-lock.json")"

[[ -n "$SWIFT_VERSION" ]] || fail "Could not read the Swift package version"
[[ "$SWIFT_VERSION" == "$PACKAGE_VERSION" ]] || \
    fail "Swift version ${SWIFT_VERSION} does not match package.json ${PACKAGE_VERSION}"
[[ "$SWIFT_VERSION" == "$LOCKFILE_VERSION" ]] || \
    fail "Swift version ${SWIFT_VERSION} does not match package-lock.json ${LOCKFILE_VERSION}"
[[ "$SWIFT_VERSION" == "$LOCKFILE_ROOT_VERSION" ]] || \
    fail "Swift version ${SWIFT_VERSION} does not match package-lock root ${LOCKFILE_ROOT_VERSION}"

if [[ -n "$TAG" ]]; then
    [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || \
        fail "Release tag must use semantic version form vMAJOR.MINOR.PATCH[-PRERELEASE]"
    TAG_VERSION="${TAG#v}"
    [[ "$SWIFT_VERSION" == "$TAG_VERSION" ]] || \
        fail "Release tag ${TAG} does not match project version ${SWIFT_VERSION}"
    [[ "$SWIFT_VERSION" != *-dev* ]] || fail "Development versions cannot be released"
    grep -F "## [${SWIFT_VERSION}]" "$PROJECT_ROOT/CHANGELOG.md" >/dev/null || \
        fail "CHANGELOG.md does not contain a ${SWIFT_VERSION} release section"
fi

printf '%s\n' "$SWIFT_VERSION"
