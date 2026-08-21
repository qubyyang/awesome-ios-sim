# Contributing

Thank you for helping make iOS Simulator automation reproducible and safe.

## Before opening a change

- Search existing issues and discussions.
- Keep mutation code behind `SimulatorControlling` and the apply confirmation boundary.
- Use public Apple tooling only. Changes that load private CoreSimulator frameworks will not be accepted.
- Represent incomplete readback as `bestEffort` or `unsupported`; do not claim exact convergence.

For substantial schema or safety-model changes, open an issue before implementation.

## Local workflow

```bash
swift build
swift test
npm ci
npm test
npm run pack:check
swift run ios-sim-state plan \
  --profile Examples/ui-tests.profile.json \
  --snapshot Examples/ui-tests.snapshot.json
```

Add fixture-based tests for state engine and parser changes. Tests must not require a locally installed
simulator unless they are explicitly marked as integration tests.

Run the opt-in live integration suite on a macOS host with a full Xcode installation and an available iOS
Simulator runtime:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  Scripts/live-integration-test.sh
```

The suite creates a uniquely named simulator, targets every destructive operation by its exact generated UDID,
and deletes that device when it finishes or fails. It never selects or mutates an existing simulator. Set
`AISS_KEEP_DEVICE=1` only when you intentionally need to retain the dedicated device for debugging. Test
reports are retained under `.build/live-integration/`.

Before preparing a tag, read [docs/RELEASING.md](docs/RELEASING.md) and run:

```bash
Scripts/release/verify-version.sh
Scripts/release/build-artifact.sh
```

Do not move an existing release tag. Breaking profile changes require a new API version and the migration
policy documented in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

Changes to `package.json`, `cordis.patch.yml`, or `dsh-plugin/` must remain compatible with the baseline
documented in `docs/DEEPSEEK_HARNESS.md`. Keep DSH integration as an adapter over the existing MCP server;
do not add a second simulator state engine or bypass the MCP apply confirmation gate.

## Commit and pull request guidance

- Keep commits focused and use imperative conventional-style subjects when practical.
- Update English and Chinese README content together when user-facing behavior changes.
- Update the JSON Schema and example profile when profile fields change.
- Include safety implications, test evidence, and compatibility impact in the pull request.
- Do not include generated `.build` content, device data, app binaries, UDIDs from private environments, or logs
  containing user paths.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
