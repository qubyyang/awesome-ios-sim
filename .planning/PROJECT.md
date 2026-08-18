# awesome-ios-sim

## Vision

Make iOS Simulator state reproducible, reviewable, and safely controllable by
humans, CI systems, and AI agents.

## Product thesis

`awesome-ios-sim` treats a simulator as declarative state rather than a pile of
one-off shell commands. A checked-in profile can be inspected, diffed, planned,
and applied with explicit safety gates.

## Users

- iOS developers who frequently rebuild test environments.
- QA and CI owners who need reproducible simulator fixtures.
- AI coding agents that need a typed, auditable control surface.

## Principles

1. Public Apple tooling first: mutate through `xcrun simctl`.
2. Plan before apply: destructive or state-changing actions are never implicit.
3. Deterministic output: stable JSON and operation ordering for review and cacheability.
4. Capability-aware: unsupported state is reported, never silently claimed.
5. Local-first: no daemon, account, or telemetry required.
6. Agent-safe: MCP schemas are narrow; mutations require explicit confirmation.

## MVP boundary

The first release is a Swift command-line and MCP product. A native SwiftUI
companion app is intentionally deferred until the state engine and safety model
are stable.

