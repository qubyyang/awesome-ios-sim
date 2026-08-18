# DeepSeek Harness plugin

[简体中文](DEEPSEEK_HARNESS.zh-CN.md)

`awesome-ios-sim` is an installable [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
bundle. It contributes two Cordis rows:

1. `@qubyyang/awesome-ios-sim/dsh-plugin` resolves the Swift MCP process without invoking a shell.
2. Harness's built-in `@deepseek-ai/dsh-mcp-client` owns the child lifecycle, discovers its tools, and
   registers them on `ctx.tools`.

The adapter does not duplicate simulator logic. DSH, standalone MCP clients, and the CLI all reach the
same Swift planner, validation, and explicit-confirmation boundary.

> DeepSeek Harness is in developer preview and may make compatibility-breaking changes. This adapter is
> tested against `@deepseek-ai/dsh` `0.1.0-rc.7` and upstream commit
> `99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`.

## Requirements

- macOS 13 or later.
- Node.js `^22.19.0` or `>=24.0.0`, `pnpm`, and DeepSeek Harness.
- Swift 6.
- Full Xcode and an iOS Simulator runtime for live simulator operations.

The plugin package is source-based. On first startup it runs the packaged Swift source with
`swift run -c release`; later starts prefer the package-local release executable when present.

## Install

Install directly from the GitHub repository into an existing DSH profile:

```bash
dsh plugin --profile web add github:qubyyang/awesome-ios-sim
dsh web
```

For reproducible environments, pin a release tag or commit:

```bash
dsh plugin --profile web add \
  github:qubyyang/awesome-ios-sim#<tag-or-commit>
```

Confirm that the bundle was added without booting an agent:

```bash
dsh --profile web --dump-config
```

The output contains layers named `@qubyyang/awesome-ios-sim` and rows named
`awesome-ios-sim-runtime` and `awesome-ios-sim-mcp`.

Remove it with:

```bash
dsh plugin --profile web remove @qubyyang/awesome-ios-sim
```

## Tools visible to DSH

Harness qualifies MCP tool names with the configured server namespace. With the default `ios_sim`
namespace, the agent receives:

| DSH tool | Purpose |
| --- | --- |
| `mcp__ios_sim__simulator_inventory` | List available runtimes and simulators. |
| `mcp__ios_sim__simulator_snapshot` | Capture the managed state of one simulator. |
| `mcp__ios_sim__simulator_diff` | Compare a profile with saved or live state. |
| `mcp__ios_sim__simulator_plan` | Generate an ordered, reviewable plan. |
| `mcp__ios_sim__simulator_apply` | Dry-run by default; mutate only with `confirm: true`. |

A safe agent workflow is inventory → snapshot → diff → plan → review → apply. Plan objects should not be
reconstructed manually before apply.

## Startup configuration

The default bundle configuration is in [`cordis.patch.yml`](../cordis.patch.yml). Two environment
variables cover common machine-local overrides:

| Variable | Purpose |
| --- | --- |
| `AWESOME_IOS_SIM_MCP_EXECUTABLE` | Use an already-built `ios-sim-state-mcp` path or PATH command. |
| `AWESOME_IOS_SIM_SWIFT` | Select the Swift executable used by the source fallback. |

For example:

```bash
swift build -c release
export AWESOME_IOS_SIM_MCP_EXECUTABLE="$PWD/.build/release/ios-sim-state-mcp"
dsh web
```

For advanced changes, override the provider row in the profile's `cordis.patch.yml`:

```yaml
- id: awesome-ios-sim-runtime
  config:
    executablePath: /opt/awesome-ios-sim/ios-sim-state-mcp
    serverName: ios_sim
    toolCallTimeoutMs: 120000
```

Cordis validates the complete configuration and fills omitted fields from the plugin schema. Available
fields are `executablePath`, `swiftCommand`, `packagePath`, `buildConfiguration` (`debug` or `release`),
`preferPrebuilt`, `serverName`, and `toolCallTimeoutMs`.

## Develop against a Harness checkout

From a built DeepSeek Harness checkout, link this repository into an isolated profile:

```bash
cd /path/to/deepseek-harness
pnpm install
pnpm run build:lib:host

DSH_HOME=/tmp/awesome-ios-sim-dsh \
  pnpm dsh plugin --profile ios-sim add /path/to/awesome-ios-sim

DSH_HOME=/tmp/awesome-ios-sim-dsh \
  pnpm dsh --profile ios-sim --dump-config
```

Run this repository's adapter tests and Swift tests before submitting a change:

```bash
npm ci
npm test
npm run pack:check
swift test
```

## Security boundary

DSH's stdio MCP bridge starts the configured command as a host child process. Like other external MCP
servers, that process is trusted executable code and runs outside the agent's workspace sandbox. Install
only revisions you trust and pin a tag or commit for managed deployments.

This does not weaken the simulator mutation boundary: `simulator_apply` still produces a dry-run unless
its `confirm` argument is exactly `true`. A DSH deployment should not automatically confirm plans from an
untrusted profile, plan file, or conversation.

