# Requirements

## State as Code

- [x] R1: Capture simulator inventory as stable JSON.
- [x] R2: Define versioned YAML/JSON-compatible desired-state profiles.
- [x] R3: Diff current and desired state without mutation.
- [x] R4: Produce a deterministic, reviewable operation plan.
- [x] R5: Apply a plan only after explicit confirmation.
- [x] R6: Record capability and best-effort metadata per state field.

## Simulator control

- [x] R7: Boot and shut down a selected simulator.
- [x] R8: Install/uninstall/launch/terminate an app.
- [x] R9: Set supported preferences and status-bar overrides.
- [x] R10: Erase a simulator behind a destructive confirmation gate.

## Agent interface

- [ ] R11: Expose discovery and operations through MCP stdio.
- [ ] R12: Support current stateless MCP requests and legacy handshake clients.
- [ ] R13: Return structured results with JSON Schema-defined inputs/outputs.

## Quality and open source

- [ ] R14: Build and test on supported macOS runners.
- [ ] R15: Provide English and Simplified Chinese README files.
- [ ] R16: Publish contribution, security, governance, and release guidance.
