# Changelog

All notable changes to this project will be documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases will use semantic versioning after the
initial alpha tag.

## [Unreleased]

### Added

- Universal arm64/x86_64 distribution archives assembled from independently built native artifacts.
- Fail-closed Developer ID signing and Apple `notarytool` automation for tagged releases.
- Generated Homebrew Formula assets bound to the notarized archive checksum.

### Changed

- Manual release-candidate runs validate the universal packaging path without requiring or exposing signing secrets.

## [0.1.0] - 2026-08-22

### Added

- Versioned `v1alpha1` Simulator State as Code profile and snapshot models.
- Capability-aware diff and deterministic operation planning.
- Safe `simctl` driver and JSON CLI with dry-run-by-default apply.
- MCP stdio server for current stateless and legacy handshake tool clients.
- Installable DeepSeek Harness bundle backed by the existing MCP server.
- Opt-in isolated live integration suite for real Xcode Simulator runtimes.
- Tag-driven arm64 and x86_64 release archives with checksums and provenance attestations.
- English and Simplified Chinese documentation, schema, examples, and CI.

### Changed

- Profile decoding now rejects unknown fields, empty identifiers, and invalid public status bar override values
  instead of silently accepting inputs that differ from the published JSON Schema.
- CI uses current official GitHub actions and enforces synchronized Swift, npm, and lockfile versions.

[Unreleased]: https://github.com/qubyyang/awesome-ios-sim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/qubyyang/awesome-ios-sim/releases/tag/v0.1.0
