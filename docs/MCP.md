# MCP integration

`ios-sim-state-mcp` is a newline-delimited JSON-RPC server over stdio. Protocol data is written only to
stdout. It launches no daemon and opens no listening port.

## Build and configure

```bash
swift build -c release --product ios-sim-state-mcp
```

Use the resulting absolute executable path in an MCP client:

```json
{
  "mcpServers": {
    "awesome-ios-sim": {
      "command": "/absolute/path/awesome-ios-sim/.build/release/ios-sim-state-mcp"
    }
  }
}
```

The MCP client process must inherit an environment where `xcode-select` and, when used, `DEVELOPER_DIR`
point to the intended Xcode installation.

## Supported protocol surface

### MCP 2026-07-28

- Stateless requests with protocol version and client capabilities in request `_meta`.
- `server/discover`.
- `ping`.
- `tools/list` with deterministic ordering, cache metadata, and JSON Schema 2020-12.
- `tools/call` with text and structured content.
- `resultType: "complete"` and server identity response metadata.
- `notifications/cancelled` accepted as a no-op for the current synchronous operations.

Resources, prompts, sampling, elicitation, subscriptions, tasks, and Streamable HTTP are not implemented.

### Legacy tool clients

The same process accepts `initialize` / `notifications/initialized`, `ping`, `tools/list`, and `tools/call`
for protocol versions `2025-11-25`, `2025-06-18`, and `2024-11-05`.

## Discovery request

```json
{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientInfo":{"name":"example","version":"1.0"},"io.modelcontextprotocol/clientCapabilities":{}}}}
```

Every current-era request must contain:

```json
{
  "_meta": {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities": {}
  }
}
```

Missing metadata returns JSON-RPC `-32602`. Unsupported versions return MCP `-32022` with the supported
version list.

## Tools

### `simulator_inventory`

No arguments. Returns runtimes and devices. Read-only.

### `simulator_snapshot`

```json
{ "udid": "SIMULATOR-UDID" }
```

Returns the managed snapshot and capability metadata. Read-only.

### `simulator_diff` and `simulator_plan`

```json
{
  "profile": { "apiVersion": "awesome-ios-sim/v1alpha1", "kind": "SimulatorState", "metadata": { "name": "example" }, "target": { "udid": "SIMULATOR-UDID" }, "spec": {} },
  "udid": "SIMULATOR-UDID"
}
```

`snapshot` is optional. When omitted, the server reads a live simulator selected by explicit `udid` or by the
profile selector. Ambiguous selectors fail instead of choosing an arbitrary device.

### `simulator_apply`

```json
{
  "plan": { "profileName": "...", "targetUDID": "...", "generatedAt": "...", "diff": [], "operations": [], "warnings": [] },
  "confirm": false
}
```

Omitted or false `confirm` returns a dry-run report and executes nothing. Only the JSON boolean `true` enables
mutation. Clients should show the plan and obtain human confirmation before sending it.

## Recommended agent policy

1. Call `simulator_inventory`.
2. Call `simulator_snapshot` for the selected UDID.
3. Call `simulator_diff` or `simulator_plan` with the desired profile.
4. Present operations, warnings, and maximum risk to the user.
5. Call `simulator_apply` without confirmation when a machine-readable dry-run receipt is useful.
6. Send `confirm: true` only after the user approves the exact plan.
7. Preserve the returned execution report.

Do not configure a client to inject `confirm: true` automatically.
