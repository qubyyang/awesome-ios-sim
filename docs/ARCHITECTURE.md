# Architecture

## Design goals

`awesome-ios-sim` separates deterministic state reasoning from host mutations. The pure layer must remain
usable in tests and CI without a simulator runtime. The host layer must be narrow, auditable, and replaceable.

## Modules

| Module | Responsibility | Host dependency |
| --- | --- | --- |
| `SimulatorStateCore` | Profile/snapshot models, capability metadata, validation, diff, deterministic planning | Foundation only |
| `SimctlDriver` | Process execution, `simctl` parsing, operation mapping, serialized apply reports | Xcode for live operations |
| `SimulatorCLI` | File-oriented human and CI interface | Driver for live operations |
| `SimulatorMCP` | MCP stdio framing, protocol compatibility, JSON Schema tools | Driver for live operations |

## Reconciliation

Planning uses a projected power state rather than treating boot and shutdown as independent commands:

1. Validate the profile schema and target selector.
2. Determine original and requested final power state.
3. Shut down first when erase is requested on a booted device.
4. Erase, if requested.
5. Boot when an online operation needs the simulator.
6. Reconcile apps, preferences, and status bar overrides in stable order.
7. Restore the requested or original final power state.

Operation IDs are derived from their final order. Diff entries and warning lists are sorted separately so
serialized output remains stable across runs with the same inputs.

## Process boundary

`FoundationCommandExecutor` never invokes a shell. It launches `/usr/bin/xcrun` with a separate argument
array and captures stdout/stderr through temporary files to avoid pipe-buffer deadlocks. Temporary output is
removed after each command.

The driver treats non-zero exit codes as data and returns them in `OperationReceipt`. The applier stops on the
first unsuccessful receipt and retains every earlier receipt. A boot operation also runs `simctl bootstatus -b`
before it is considered successful.

## Concurrency

Each `SimulatorPlanApplier` serializes apply calls with a lock, and operations inside a plan are always serial.
The current CLI and stdio MCP server are single-process tools. Cross-process coordination is not yet provided;
users should not run multiple confirmed applies against the same UDID concurrently.

## Capability semantics

- `exact`: the driver can read and write enough state to compare convergence accurately.
- `bestEffort`: Apple exposes mutation but incomplete or runtime-dependent readback.
- `unsupported`: the operation is skipped and represented as an unsupported diff plus warning.

No private CoreSimulator framework is used to turn a best-effort capability into a misleading exact claim.

## Trust boundaries

- Profiles, snapshots, and plans are untrusted input and decoded into narrow types.
- A plan is executable intent; CLI and MCP validate that every operation targets `plan.targetUDID` and that
  operation IDs are unique.
- Mutation requires confirmation at the apply boundary, independent of per-operation annotations.
- MCP tool annotations are descriptive only; server-side confirmation enforcement is authoritative.

## Deferred decisions

- Cross-process device locks and resumable journals.
- YAML parsing. The MVP accepts JSON only.
- Streamable HTTP transport and its authorization model.
- Direct filesystem indexing and orphan-directory cleanup.
- Native SwiftUI presentation.

