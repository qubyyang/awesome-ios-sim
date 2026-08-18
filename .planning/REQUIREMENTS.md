# Requirements

## State as Code

- [ ] R1: Capture simulator inventory as stable JSON.
- [ ] R2: Define versioned YAML/JSON-compatible desired-state profiles.
- [ ] R3: Diff current and desired state without mutation.
- [ ] R4: Produce a deterministic, reviewable operation plan.
- [ ] R5: Apply a plan only after explicit confirmation.
- [ ] R6: Record capability and best-effort metadata per state field.

## Simulator control

- [ ] R7: Boot and shut down a selected simulator.
- [ ] R8: Install/uninstall/launch/terminate an app.
- [ ] R9: Set supported preferences and status-bar overrides.
- [ ] R10: Erase a simulator behind a destructive confirmation gate.

## Agent interface

- [ ] R11: Expose discovery and operations through MCP stdio.
- [ ] R12: Support current stateless MCP requests and legacy handshake clients.
- [ ] R13: Return structured results with JSON Schema-defined inputs/outputs.

## Quality and open source

- [ ] R14: Build and test on supported macOS runners.
- [ ] R15: Provide English and Simplified Chinese README files.
- [ ] R16: Publish contribution, security, governance, and release guidance.

