# SimpleSimulatorManager 仓库分析与新项目技术建议

> 分析日期：2026-08-18  
> 仓库：[Heckscheibe/SimpleSimulatorManager](https://github.com/Heckscheibe/SimpleSimulatorManager)  
> 源码基线：`develop` 分支提交 [`7852646`](https://github.com/Heckscheibe/SimpleSimulatorManager/commit/7852646f4a01b2b0217e6933ff0de87c55318d1f)，提交时间 2026-08-16。  
> 方法：完整源码静态阅读、测试与工程配置审计、GitHub 在线元数据核对。当前机器没有完整 Xcode，未执行构建和测试；结论中不会把静态检查冒充实测性能。

## 结论先行

SimpleSimulatorManager 值得参考，但它并不是一个完整的“iOS 模拟器状态管理器”。它更准确的定位是：

1. 把 CoreSimulator 的 UUID 文件树翻译成可理解的设备、App、数据容器和 App Group，并在 Finder 中打开；
2. 通过 FSEvents 监听 App 安装、更新和删除，提供最近使用 App；
3. 用 `simctl` 查找无效模拟器、删除无效对象，以及擦除单台或全部模拟器。

对于你的新项目，最合适的默认方案仍然是 **Swift 端到端实现**，而不是为了“性能”改写成 Rust、C++ 或 Go。这个项目的大头开销是文件系统 I/O、plist 解码和 `simctl` 子进程，换语言不会让 `simctl erase`、`simctl delete` 或 Finder 更快。最有效的优化是减少扫描、增量索引、缓存、后台加载和批量执行。

如果你的长期目标包含独立 CLI、可嵌入引擎、远程调用或非 Swift 客户端，可以采用“SwiftUI/AppKit 外壳 + Rust 核心”的混合方案；但 Rust 的价值主要是可复用的系统核心和内存安全边界，不是本项目场景下必然更快。

真正值得做出的产品差异，不是另一个 `simctl` GUI，而是 **Simulator State as Code**：把设备、App、权限、位置、外观、状态栏、推送、媒体和测试数据表达成可导出、可比较、可重复应用的状态配置。

## 1. 仓库快照与项目地图

截至分析日，GitHub 页面显示 51 stars、1 fork、6 个 open issues、1 个 pull request、161 次提交；默认分支为受保护的 `develop`。项目当前版本为 1.3.1（build 54），MIT 许可证，最低 macOS 15。

静态规模：

| 类别 | 数量/规模 | 说明 |
|---|---:|---|
| 生产 Swift 文件 | 48 / 约 4,589 行 | 一个 macOS App target |
| 测试 Swift 文件 | 21 / 约 2,605 行 | Swift Testing |
| 测试声明 | 14 个 suite / 94 个 `@Test` | 参数化测试实际 case 更多 |
| UI 测试源码 | 0 | 只有空 target 与 Info.plist |
| 第三方 Swift 运行时依赖 | 0 | 只使用 Apple 系统框架 |
| 发布依赖 | Fastlane/Ruby | Developer ID、公证、ZIP、Homebrew tap |

技术栈：Swift 6、SwiftUI、AppKit、Combine、Observation、Foundation、FSEvents、Carbon、`os_log`。主 target 开启完整并发检查与 Hardened Runtime；App Sandbox 关闭。

主要模块：

| 模块 | 职责 |
|---|---|
| `SimulatorManagerApp` | composition root，装配服务、ViewModel、菜单和设置窗口 |
| `DeviceManager` | 设备、设备类型、最近 App 的中央状态源 |
| `AppDiscoveryService` | 扫描 Bundle/Data/AppGroup 目录并关联元数据 |
| `FolderMonitor` / `AppFolderMonitor` | FSEvents 封装与按设备监听 |
| `DeviceAppMonitoringService` | 快照 diff、单设备刷新、最近 App 更新 |
| `SimulatorCleanupService` | `simctl` 与磁盘目录交叉验证、生成清理候选、执行删除 |
| `SimulatorResetService` | shutdown/erase 单设备或全部设备 |
| `GlobalHotkeyService` | Carbon 全局快捷键 |
| `MenuBarMenuPresenter` | 用 AppKit 找到并点击 MenuBarExtra 的状态按钮 |
| ViewModels / Views | 菜单展示、设置、清理、擦除和错误状态 |

## 2. 真实架构与数据流

```text
SwiftUI MenuBarExtra / Settings Window
                 │
                 ▼
          ViewModels（主线程）
                 │
       ┌─────────┼───────────┐
       ▼         ▼           ▼
 DeviceManager  Cleanup     Reset
       │         Service     Service
       │           │           │
       │           └──── xcrun simctl ────┐
       │                                  │
       ├─ AppDiscoveryService             │
       │     └─ CoreSimulator 文件树/plist│
       │                                  │
       └─ DeviceAppMonitoringService      │
             └─ FSEvents → debounce       │
                    → 仅刷新变化设备       │
                                        CoreSimulator
```

### 启动路径

`SimulatorManagerApp.init()` 创建 `DeviceManager`；`DeviceManager.init()` 立即同步调用 `loadDevices()`。它遍历：

```text
~/Library/Developer/CoreSimulator/Devices/<UDID>/device.plist
```

然后逐台设备继续读取：

```text
data/Containers/Bundle/Application/*/*.app/Info.plist
data/Containers/Data/Application/*/.com.apple.mobile_container_manager.metadata.plist
data/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist
```

设备和 App 数据通过 Combine 的 `CurrentValueSubject` 发布给 `SimulatorManagerViewModel`。视图层使用 SwiftUI，但 Finder、全局快捷键和菜单控制分别落到 AppKit 与 Carbon。

### App 与数据容器的关联

仓库当前实现有一个正确且值得保留的优化：先把所有 Data Container 的 metadata 按 bundle identifier 建成字典，再与 App Bundle 的 `Info.plist` 关联。由原本可能的 O(App × Container) 变成 O(App + Container)，重复容器则选 modification date 更新者。

### 实时更新

每个已知设备建立一个 FSEvents 监听器：有 App 时监听 `Bundle/Application`，没有 App 时暂时监听更宽的 `data` 目录。FSEvents latency 为 0.1 秒，再经过 3 秒 debounce。事件到达后只重扫发生变化的设备，比较前后 bundle ID 与 modification date，生成 installed、updated、removed 事件。

Apple 将 FSEvents 定义为目录层级变化的轻量通知接口；事件本身只表示“某处变了”，因此“事件 + 状态快照 + diff”正是合适的设计。[Apple FSEvents 文档](https://developer.apple.com/documentation/coreservices/file_system_events)

### 修改与破坏性操作

项目没有链接私有 CoreSimulator.framework。正式设备操作都通过 `/usr/bin/xcrun simctl`：

- 清理扫描：`list devices --json`、`list runtimes --json`；
- 删除已登记但不可用设备：`delete <UDID>`；
- 擦除：先 `shutdown`，再 `erase`；
- 孤儿目录：使用 `FileManager.trashItem` 移到废纸篓，不直接永久删除。

这是稳妥的边界。Apple 也将 `simctl` 定义为 Simulator 的官方命令行控制入口，并建议以 `xcrun simctl help` 获取当前 Xcode 对应的命令能力。[Apple Xcode 命令行工具参考](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)

## 3. 仓库已经提供的能力

### 3.1 设备与平台

- 枚举本机模拟器设备；
- 读取 UDID、名称、runtime、设备类型、最近启动时间和开关机状态；
- 识别 iPhone、iPad、Watch、Apple TV、Vision Pro、iPod touch；
- 按设备名称和 OS 版本组织菜单；
- 按平台隐藏或显示设备。

### 3.2 App、容器与 Finder

- 枚举 iOS/iPadOS 和 watchOS App；
- 读取 display name、bundle identifier、package URL、data container URL；
- 打开模拟器根目录、所有 App Data 目录、所有 App Bundle 目录；
- 打开单 App 数据容器、App Bundle 所在目录、UserDefaults 目录；
- 枚举 App Group，并打开 Group 目录或 Group UserDefaults；
- 识别 iOS App 内是否含 Watch App，以及读取 Watch companion bundle ID（目前 UI 未使用）。

### 3.3 最近 App 与变化检测

- 初次启动按 App Bundle/Data Container 较新的 modification date 构造最近列表；
- 最多保留 20 条；
- 以 bundle ID + device UDID 去重；
- FSEvents 驱动安装、更新和删除检测；
- 只刷新受影响设备。

### 3.4 清理

- 找出 `simctl` 报告为 unavailable 的设备；
- 找出 runtime 缺失、device type 缺失的设备；
- 找出磁盘存在但 CoreSimulator 未登记的孤儿目录；
- 识别缺失或不可读的 `device.plist`；
- 显示原因、详细错误、平台、OS、磁盘占用、最近启动时间和 UDID；
- 支持单个、按 OS 分组、全部清理；
- 优先使用 `simctl` 返回的 `dataPathSize`，必要时递归计算 allocated size。

### 3.5 擦除与设置

- 单设备 shutdown + erase；
- shutdown all + erase all；
- 破坏性操作二次确认；
- 全局快捷键打开菜单，默认 `⌃⌥⌘S`，支持录制、清除和恢复默认；
- 每 24 小时检查 GitHub Release 更新；
- Developer ID 签名、公证、ZIP 和 Homebrew Cask 发布脚本。

## 4. 功能边界、问题和 README 差异

这些问题不等于项目质量差，但会决定你是否应该 fork 它。

### 4.1 它不是完整的模拟器状态管理器

当前没有：创建、克隆、重命名、正常删除、独立 boot/shutdown、runtime 管理、安装/卸载/启动/终止 App、deep link、位置、语言/地区/时区、深浅色、权限、推送、媒体、剪贴板、截图/录屏、状态栏、Keychain、日志、快照、状态配置、CLI/API。

项目自己的 open issues 也把 boot/shutdown、App launch/terminate/uninstall、deep link、push、privacy reset、media seed 等列为后续路线，而不是现有能力：[roadmap issue #28](https://github.com/Heckscheibe/SimpleSimulatorManager/issues/28)。

### 4.2 启动期同步 I/O 是首要性能问题

`DeviceManager.init()` 在应用装配阶段同步遍历全部设备、App、Data Container 和 App Group。模拟器或 App 多时，这会直接增加菜单栏应用冷启动时间。Apple 的建议是把昂贵初始化延后或移入异步后台队列。[Reducing your app’s launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)

正确改法不是换 Rust，而是：

1. 先发布空/缓存快照，让菜单立即可用；
2. 后台 actor 扫描；
3. 每个设备完成后增量发布，或全部完成后一次发布；
4. 对 plist 的 URL + mtime + size 建缓存；
5. 后续只处理 FSEvents 指出的设备。

### 4.3 App Group 关联是启发式，会漏数据

实现把 `group.xxx` 去掉第一段，然后用 App bundle ID `contains` 判断关联。这不等价于读取 App entitlements，合法 App Group 可能与 bundle ID 不满足子串关系，也可能误匹配。新项目应优先通过 `simctl get_app_container` 的能力探测、签名 entitlement 或明确的 group container 元数据关联，而不是字符串猜测。

### 4.4 平台解码存在隐藏边界

App 的 `DTPlatformName` 枚举只接受 `iphonesimulator` 与 `watchsimulator`。README 明示 visionOS App discovery 不支持，但 tvOS 的 `appletvsimulator` 同样可能解码失败。iPad App 通常仍使用 `iphonesimulator`，所以可工作。

### 4.5 设备状态模型过窄

`DeviceState` 只接受 raw value 1（Off）和 3（Running）。创建中、启动中、关机中等过渡状态会导致整个 `device.plist` 解码失败，设备可能暂时从 UI 消失。新的模型应有 `.creating/.shutdown/.booting/.booted/.shuttingDown/.unknown(rawValue)`，并以 `simctl list --json` 为权威动态状态源。

### 4.6 设备集合本身不实时

FSEvents 只监听当前已知设备的 App 目录，没有监听 CoreSimulator 根目录。外部创建、删除、重命名模拟器不会自然触发设备列表更新；生产代码中的 `updateDevices()` 也没有常规调用入口。新项目应增加根目录/`simctl list` 事件源，并对集合变化与内容变化分层处理。

### 4.7 文案与路径并不完全一致

- UI 的 per-App 菜单只有 Documents、App Package、User Defaults，没有 README 所说的独立 App Folder；
- 名为 `appDocumentsFolderURL` 的字段实际指向整个 Data Container 根目录，没有追加 `/Documents`；
- App Package 动作打开 `.app` 的父目录，并没有直接选中 package。

这类命名偏差会影响 API 设计。新项目应明确区分：`dataContainer`、`documents`、`library`、`caches`、`tmp`、`appBundle`、`bundleContainer`。

### 4.8 全量 Reset 有重复扫描

Reset service 完成时发布事件触发一次 `resetAndLoadDevices()`；Reset ViewModel 随后又主动调用一次。全量 I/O 会重复。应让 operation coordinator 成为唯一刷新责任方。

### 4.9 更新检查任务生命周期不完整

`GitHubView.onAppear` 每次启动一个永久 24 小时循环，但没有保存或取消 Task handle。菜单反复出现时可能累计多个周期任务。应将 update service 作为应用级单例，并确保 start 幂等。

### 4.10 权限与分发边界

App Sandbox 明确关闭，以直接读取 `~/Library/Developer/CoreSimulator`。这使 Mac App Store 分发不可行，信任模型依赖开源审计、Developer ID 与公证。Apple 规定 Mac App Store 应用必须启用 App Sandbox；sandbox 对文件系统访问也有明确限制。[App Sandbox 文档](https://developer.apple.com/documentation/security/app-sandbox)

## 5. 性能分析：瓶颈在哪里

按预期影响排序：

| 优先级 | 热点 | 本质 | 建议 |
|---:|---|---|---|
| P0 | 启动同步全量扫描 | 大量目录遍历与小文件 I/O | 后台 actor、缓存快照、延迟加载 |
| P0 | 每次变化重扫整台设备 | FSEvents 只告诉“目录变了” | 保存 per-device index，只更新改变的 container |
| P1 | 清理时递归计算目录大小 | 可能访问几十万文件 | 按需计算、限定并发、缓存、优先 `dataPathSize` |
| P1 | 3 秒 debounce | CPU 省，但体感慢 | benchmark 后降到 250–750ms，连续构建时自适应合并 |
| P1 | 每台设备一个 FSEvent stream/queue | 大量历史设备会累积 stream、queue 和 timer | 用一个或少量 stream 监听多路径，并按事件 path 分发 |
| P1 | 同设备 refresh 可重复排队 | Task 无句柄，旧快照可能触发重复 diff | 每 UDID 一个在途任务 + dirty generation |
| P1 | `xcrun`/`simctl` 进程启动 | 固定子进程开销 | 缓存 simctl 路径、合并查询、避免重复刷新 |
| P1 | 同步 Process runner | 无 timeout/cancel，stdout/stderr 混合 | 异步 drain、输出上限、deadline、取消时终止进程 |
| P2 | 混合 Combine/Observation | 更新路径复杂、逃生式并发标记 | actor 管状态、UI 只在 MainActor 观察快照 |
| P2 | 顺序批量删除 | 安全但慢 | 每设备串行，设备之间有界并发；破坏性操作默认保守 |

代码已经有两处好优化：

- Container 字典把匹配降为 O(A + C)；
- Cleanup 同时加载 simctl devices、runtimes 和目录记录。

当前 FSEvents callback 丢弃了 event path、flags 和 event ID，所以任何小变化最终仍会重扫该设备全部 Bundle、Data Container 与 App Group。更好的实现应保留 path/flags，并使用 `kFSEventStreamCreateFlagFileEvents` 做细粒度 reconcile；只有出现 `MustScanSubDirs`、`UserDropped`、`KernelDropped` 等事件时才退化为全量扫描。

当前 `Process.execute` 使用阻塞的 `readDataToEndOfFile()`/`waitUntilExit()`，没有 timeout，也不会随 Swift Task cancellation 终止子进程；同时 stdout/stderr 合并、输出完整留在内存。参数为空时还会启用 `/bin/sh -c`，虽然现在没有调用点，但作为公共 helper 会留下未来命令注入风险。新项目应删除 shell 模式，让所有命令都走 executable URL + 参数数组。

但 `DeviceManager` 使用 `@unchecked Sendable`，`SimulatorResetService` 有 `nonisolated(unsafe)` 状态。它们能通过 Swift 6 检查，却把正确性责任交给人工约定。新实现更适合用 actor 隔离 mutable state，并把 UI 快照建成不可变 `Sendable` 值类型。

### 推荐 benchmark

不要先争论语言，先建立这些基线：

| 指标 | 数据集 |
|---|---|
| 冷启动到菜单可交互 p50/p95 | 10/50/100 台设备，各 0/5/20 个 App |
| 首次完整索引耗时与峰值 RSS | 同上 |
| 单 App 安装到 UI 更新延迟 | 空闲、连续 build 10 次 |
| 单设备增量刷新读取文件数 | 安装、更新、卸载各一次 |
| Cleanup scan p50/p95 | 10/100/300GB 模拟器数据 |
| 空闲 CPU、唤醒次数、FSEvents 回调数 | 30 分钟空闲 + Xcode build |
| 每类 simctl 命令耗时 | 首次、热启动、多 Xcode 配置 |
| Process 可靠性 | timeout、取消、超大 stderr、异常退出 |

通过 `os_signpost`、Instruments、XCTest/Swift Testing performance fixture 持续记录。Apple 也建议用 Instruments 同时观察 launch、阻塞 I/O、SwiftUI 更新、并发任务与能耗。[Testing and performance](https://developer.apple.com/documentation/technologyoverviews/testing-and-performance)

## 6. Swift、Rust、C++、Go 的选择

| 方案 | 性能潜力 | macOS/SwiftUI 集成 | 工程成本 | 结论 |
|---|---|---|---|---|
| Swift + SwiftUI/AppKit | 足够高，原生编译；I/O 场景不是语言瓶颈 | 最佳 | 最低 | **默认推荐** |
| Swift UI + Rust Core | 扫描/索引核心可控，适合复用 CLI | 需 C ABI/IPC 桥接 | 中高 | 仅在产品需要独立引擎时采用 |
| 纯 Rust GUI | 核心强，但 macOS 原生菜单/窗口/Carbon/FSEvents 绑定成本高 | 较弱 | 高 | 不推荐作为首版 |
| Objective-C/C++ | 可直接调用 C API，但没有端到端收益 | AppKit 可用，SwiftUI 差 | 高，安全性较差 | 不推荐 |
| Go | CLI 和并发易做，但 GC/runtime 与 Cocoa UI 不匹配 | 弱 | 中 | 可做辅助 CLI，不做主 App |
| Electron/Tauri | 开发快，但对菜单栏工具通常引入更多内存和 UI 桥接 | 非原生或半原生 | 中 | 性能目标下不优先 |

Swift 本身是编译并优化的原生语言，并不是脚本层；官方语言目标明确包含安全和性能。[About Swift](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/aboutswift/)

Rust 可以通过 C ABI 与 Swift 或 Apple C APIs 连接，但 FFI 会引入 ABI、生命周期、错误模型和构建分发成本；Rust 官方也将跨语言调用标为需要显式 ABI 和安全包装的边界。[Rust FFI](https://doc.rust-lang.org/stable/rust-by-example/std_misc/ffi.html)

因此：

- 如果只有一个 macOS App：选 Swift；
- 如果从第一天就要 `iossim` CLI + GUI + 可嵌入 library：仍可先做 Swift Package；
- 如果未来要让非 Swift 客户端长期调用、或索引器在 benchmark 中成为明确 CPU/RSS 瓶颈，再将 `SimulatorIndex` 单独替换为 Rust；
- 不要因为“Rust 理论上快”就承担全项目双语言复杂度。

## 7. 推荐的新项目架构

建议从一开始拆成 Swift Package，而不是把所有代码放进一个 Xcode App target：

```text
awesome-ios-sim/
├── Package.swift
├── Sources/
│   ├── SimulatorCore/       # 模型、状态快照、diff、plan、错误
│   ├── SimctlDriver/        # ProcessRunner、JSON decoder、能力探测
│   ├── SimulatorIndex/      # 文件索引、plist、FSEvents、缓存
│   ├── StateProfiles/       # YAML/JSON profile、校验、迁移
│   └── SimulatorCLI/        # JSON 输出、脚本与 CI
├── Apps/
│   └── SimulatorManager/    # SwiftUI/AppKit，仅展示与确认
├── Tests/
│   ├── Fixtures/            # 脱敏 CoreSimulator/simctl JSON fixture
│   ├── Unit/
│   └── Integration/
└── .github/workflows/
```

### 7.1 `SimctlDriver`：唯一命令边界

用 actor 串行化同一设备的命令，不同设备允许有界并发：

```swift
actor SimctlDriver {
    func inventory() async throws -> SimulatorInventory
    func execute(_ operation: SimulatorOperation) async throws -> OperationResult
    func capabilities() async throws -> SimctlCapabilities
}
```

关键点：

- 通过 `/usr/bin/xcrun` 解析当前选定 Xcode，不假定固定工具路径；
- 支持 `DEVELOPER_DIR`，把 Xcode installation 作为上下文；
- 启动时解析 `simctl help` 建能力矩阵，不假定所有 Xcode 都支持同一命令；
- stdout/stderr 分离，保留 exit code、命令耗时和可安全展示的参数；
- 破坏性命令提供 dry-run 与确认 token；
- 禁止直接调用私有 CoreSimulator.framework。

### 7.2 `SimulatorIndex`：读模型与增量缓存

- 以 `simctl list --json` 为设备、runtime、动态 state 的权威来源；
- 以文件系统补充 App container、App Group、磁盘占用和 mtime；
- FSEvents 监听 CoreSimulator 根目录和按设备 App 目录；
- 缓存键包含 Xcode context、UDID、path、mtime、size；
- 首次扫描后台化，UI 可先展示缓存快照；
- App Group 不使用 bundle 字符串猜测。

### 7.3 `StateProfiles`：你的核心差异化

建议定义可版本化的 JSON/YAML：

```yaml
schema: 1
target:
  platform: iOS
  device: iPhone 17 Pro
  runtime: "26.0"
state:
  booted: true
  appearance: dark
  locale: zh_CN
  location: [31.2304, 121.4737]
  permissions:
    camera: grant
    photos: grant
  statusBar:
    time: "09:41"
    batteryLevel: 100
  apps:
    - bundleId: com.example.app
      launch: true
```

核心命令：

```text
iossim inventory --json
iossim snapshot <udid> --output state.yaml
iossim diff <udid> state.yaml
iossim plan <udid> state.yaml
iossim apply <udid> state.yaml --dry-run
iossim apply <udid> state.yaml
```

不是所有 simulator state 都可读取或回滚，所以 profile engine 必须把每个字段标为：`observable`、`applicable`、`reversible`、`bestEffort`，不要承诺伪事务。

### 7.4 第一版能力优先级

**MVP**

- inventory：设备、runtime、动态状态、App；
- boot/shutdown/erase/create/delete；
- install/uninstall/launch/terminate/openurl；
- App/Data/Documents/Library/Caches/tmp/App Group 路径；
- CLI JSON 输出 + macOS 菜单 UI；
- 所有破坏性动作 dry-run/确认/日志。

**V1**

- permissions、appearance、location、status bar、push、media、screenshot/video、keychain certificate；
- presets/profile apply；
- 搜索与最近 App；
- 空间治理与清理建议。

Apple 已公开展示 `simctl` 对 privacy、push、status bar、video 和 keychain 等场景的支持，可作为能力规划的官方依据：[WWDC20 Become a Simulator expert](https://developer.apple.com/videos/play/wwdc2020/10647/)。位置场景与 waypoint 支持也见 [Xcode 14 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-14-release-notes)。

**V2**

- profile export/diff、团队共享模板；
- 批量矩阵执行；
- 插件/JSON-RPC；
- 日志与诊断；
- 可选本地 XPC helper。

## 8. 安全与可靠性设计

模拟器工具的“快”不能建立在误删数据上：

1. 所有 erase/delete/reset 显示精确目标、UDID、runtime、预计释放空间；
2. 默认单目标操作，批量操作必须二次确认；
3. 孤儿目录优先移到废纸篓；
4. 每设备 operation lock，防止 boot/erase/install 竞态；
5. 操作 journal 记录开始、结束、命令、exit code、耗时和刷新结果；
6. 不直接修改运行中设备的内部 plist；
7. 集成测试使用 fixture/fake ProcessRunner，绝不 erase 用户真实设备；
8. CoreSimulator 磁盘结构视为非稳定接口，解析失败必须降级而不是删除；
9. 支持多 Xcode 与 `DEVELOPER_DIR`，把每个缓存绑定到对应 Xcode context；
10. App Sandbox 关闭的情况下，保持零遥测、最小网络面、Developer ID、公证和可审计发布。

执行孤儿目录删除前还应重新做一次 TOCTOU 校验：canonicalize URL，拒绝 symlink，确认目标是 CoreSimulator `Devices` 根目录的直接 UUID 子目录，并重新核对 metadata/UDID。单设备 API 使用强类型 UUID，禁止 `all`、`booted`、`unavailable` 等 `simctl` 特殊 token 混入单设备删除入口。

## 9. 测试与开源工程成熟度

现仓库的 94 个测试是优点，尤其是：App diff、FSEvents、Carbon 快捷键、清理规则、ViewModel 状态。但测试分布不均：

- `DeviceManager` 无直接测试；
- `AppDiscoveryService` 无测试；
- `SimulatorResetService` 无直接测试；
- Cleanup 未测真实 simctl JSON decoder/Process 边界；
- `GithubService`、路径与 plist decoder 缺测试；
- UI 测试 target 没有源码；
- Combine 测试较多依赖固定 sleep；
- 没有 GitHub Actions、coverage、test plan、CONTRIBUTING、SECURITY、CHANGELOG；
- 测试 README 推荐 `swift test`，但仓库没有 `Package.swift`，并且还描述已经不存在的测试目录。

发布脚本可以完成本机 Developer ID 构建、公证和 Homebrew tap 更新，但没有在 release lane 前强制 test/lint，版本输入是交互式 prompt，GitHub Release 仍需人工上传，Homebrew tap 会从本机直接 push。它适合个人维护，不是理想的社区发布骨架。

你的项目应从第一天加入：

- macOS GitHub Actions：build、unit、fixture integration、lint；
- 固定 SwiftFormat/SwiftLint 版本，构建阶段只 `--lint`，不自动改源码；
- Swift 6 测试 target 与完整并发检查；
- 可注入 `ProcessRunner`、`FileSystem`、`Clock`、`WorkspaceOpener`；
- snapshot fixture 覆盖多个 Xcode/simctl JSON 版本；
- 非交互 release workflow、签名公证、SBOM、checksum、Homebrew PR；
- `SECURITY.md` 解释关闭 Sandbox、访问范围和漏洞报告渠道。

## 10. 最终取舍

### 可以直接借鉴

- FSEvents + 快照 diff，而不是轮询；
- 只刷新发生变化的设备；
- App/Data Container O(A + C) 关联；
- 清理“先检测并解释、再确认执行”；
- 已登记设备用 simctl，孤儿目录进废纸篓；
- 协议注入、薄 View、服务层承载系统逻辑；
- 零第三方运行时依赖与原生菜单栏体验。

### 不建议直接 fork 延伸

- 所有能力都在一个 App target；
- 启动同步全盘扫描；
- 直接读取磁盘结构作为主要设备状态源；
- App Group 字符串启发式；
- `@unchecked Sendable`/`nonisolated(unsafe)` 作为并发逃生口；
- Combine、ObservableObject 与 Observation 混用；
- 无 CLI、无稳定 public API、无状态 profile；
- 缺 CI 与系统边界测试。

### 推荐决策

**用 Swift 6 构建第一版；先拆 `SimulatorCore + SimctlDriver + SimulatorIndex + CLI + SwiftUI App`。** 把时间投入到增量索引、可复现状态 profile、安全操作计划和多 Xcode 兼容上。这些会形成真正的产品壁垒，而不是把 Swift 换成更低层语言。

只有当 benchmark 证明“索引器 CPU/RSS”是实际瓶颈，或者你明确需要跨语言嵌入引擎时，再把 `SimulatorIndex` 或 `StatePlanner` 替换为 Rust，并通过稳定 C ABI 或本地 JSON-RPC 连接 Swift UI。
