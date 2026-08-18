# DeepSeek Harness 插件

[English](DEEPSEEK_HARNESS.md)

`awesome-ios-sim` 可以作为 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的
可安装 bundle 使用。它向 Cordis 配置贡献两条记录：

1. `@qubyyang/awesome-ios-sim/dsh-plugin` 负责定位 Swift MCP 进程，且不经过 Shell。
2. Harness 内置的 `@deepseek-ai/dsh-mcp-client` 负责子进程生命周期、工具发现，并把工具注册到
   `ctx.tools`。

适配层不复制模拟器业务逻辑。DSH、普通 MCP Client 与 CLI 最终都使用同一套 Swift planner、
校验逻辑和显式确认门禁。

> DeepSeek Harness 目前处于 developer preview，可能发生破坏性兼容变更。本适配器的兼容基线为
> `@deepseek-ai/dsh` `0.1.0-rc.7` 与上游提交
> `99f6f02fecdb7dff40c3fbc9470f5907c29f74ca`。

## 环境要求

- macOS 13 或更高版本。
- Node.js `^22.19.0` 或 `>=24.0.0`、`pnpm` 与 DeepSeek Harness。
- Swift 6。
- 实时模拟器操作需要完整 Xcode 与 iOS Simulator Runtime。

插件包以源码形式分发。首次启动时会通过 `swift run -c release` 运行包内 Swift 源码；后续启动若
检测到包内已有 release 可执行文件，会优先直接使用它。

## 安装

从 GitHub 直接安装到已有 DSH profile：

```bash
dsh plugin --profile web add github:qubyyang/awesome-ios-sim
dsh web
```

生产或可复现环境应固定 Release Tag 或 Commit：

```bash
dsh plugin --profile web add \
  github:qubyyang/awesome-ios-sim#<tag-or-commit>
```

不启动 Agent，仅检查 bundle 是否已加入：

```bash
dsh --profile web --dump-config
```

输出中应包含 `@qubyyang/awesome-ios-sim` 配置层，以及 `awesome-ios-sim-runtime`、
`awesome-ios-sim-mcp` 两条记录。

卸载命令：

```bash
dsh plugin --profile web remove @qubyyang/awesome-ios-sim
```

## DSH 中可见的工具

Harness 会给 MCP 工具名加上 Server Namespace。使用默认的 `ios_sim` 后，Agent 可以看到：

| DSH 工具 | 用途 |
| --- | --- |
| `mcp__ios_sim__simulator_inventory` | 列出可用 Runtime 与模拟器。 |
| `mcp__ios_sim__simulator_snapshot` | 采集单个模拟器的托管状态。 |
| `mcp__ios_sim__simulator_diff` | 比较 Profile 与保存或实时状态。 |
| `mcp__ios_sim__simulator_plan` | 生成有序、可审查的 Plan。 |
| `mcp__ios_sim__simulator_apply` | 默认 Dry-run；仅 `confirm: true` 时修改。 |

推荐的安全工作流是 inventory → snapshot → diff → plan → 人工审查 → apply。执行前不要让 Agent
手工拼装或改写 Plan 对象。

## 启动配置

默认 Bundle 配置位于 [`cordis.patch.yml`](../cordis.patch.yml)。常见的本机差异可以通过两个环境
变量处理：

| 变量 | 用途 |
| --- | --- |
| `AWESOME_IOS_SIM_MCP_EXECUTABLE` | 使用已经构建的 `ios-sim-state-mcp` 路径或 PATH 命令。 |
| `AWESOME_IOS_SIM_SWIFT` | 指定源码回退模式使用的 Swift 可执行文件。 |

例如：

```bash
swift build -c release
export AWESOME_IOS_SIM_MCP_EXECUTABLE="$PWD/.build/release/ios-sim-state-mcp"
dsh web
```

需要高级定制时，可以在 Profile 的 `cordis.patch.yml` 中覆盖 Provider 记录：

```yaml
- id: awesome-ios-sim-runtime
  config:
    executablePath: /opt/awesome-ios-sim/ios-sim-state-mcp
    serverName: ios_sim
    toolCallTimeoutMs: 120000
```

Cordis 会校验完整配置，并用插件 Schema 补齐省略字段。可配置项包括 `executablePath`、
`swiftCommand`、`packagePath`、`buildConfiguration`（`debug` 或 `release`）、`preferPrebuilt`、
`serverName` 与 `toolCallTimeoutMs`。

## 在 Harness 源码仓库中开发

在已经构建的 DeepSeek Harness Checkout 中，把本仓库链接到隔离 Profile：

```bash
cd /path/to/deepseek-harness
pnpm install
pnpm run build:lib:host

DSH_HOME=/tmp/awesome-ios-sim-dsh \
  pnpm dsh plugin --profile ios-sim add /path/to/awesome-ios-sim

DSH_HOME=/tmp/awesome-ios-sim-dsh \
  pnpm dsh --profile ios-sim --dump-config
```

提交修改前运行适配层测试和 Swift 测试：

```bash
npm ci
npm test
npm run pack:check
swift test
```

## 安全边界

DSH 的 stdio MCP Bridge 会把配置的命令作为宿主子进程启动。和其他外部 MCP Server 一样，该
进程属于受信任的可执行代码，运行在 Agent Workspace Sandbox 之外。只安装可信 Revision；受管
环境应固定 Tag 或 Commit。

这不会削弱模拟器修改门禁：除非 `simulator_apply` 的 `confirm` 参数严格等于 `true`，否则仍然
只会返回 Dry-run。DSH 部署不应自动确认来自不可信 Profile、Plan 文件或对话内容的执行计划。

