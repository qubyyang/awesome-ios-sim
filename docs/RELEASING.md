# Release process / 发布流程

## English

Release automation compiles separate Apple Silicon and Intel slices, verifies both native archives, and merges
the CLI and MCP server into one universal ZIP. Tagged releases must then pass Developer ID signing with hardened
runtime and secure timestamps, Apple `notarytool`, Homebrew Formula generation, SHA-256 verification, and GitHub
artifact attestation. See [the distribution contract](DISTRIBUTION.md) for credential names and trust boundaries.

Prepare a release commit:

1. Set the intended semantic version in
   `Sources/SimulatorStateCore/Version.swift`, `package.json`, and `package-lock.json`.
2. Move relevant changelog entries from `Unreleased` to `## [VERSION] - YYYY-MM-DD`.
3. Run `Scripts/release/verify-version.sh`, the full test suite, and
   `Scripts/release/build-artifact.sh` on at least one supported architecture.
4. Commit and push the release preparation.
5. Run the `Release` workflow manually from that commit. This release-candidate run must validate both native
   architectures, the unsigned universal archive, and the generated Formula. It does not read signing secrets,
   contact Apple's notary service, attest artifacts, or publish a Release.
6. Confirm all five protected distribution secrets listed in `DISTRIBUTION.md` are configured.
7. Create and push an annotated tag, for example `v0.2.0`. The tag must point at the reviewed release commit.

The tag-triggered workflow validates version and changelog alignment before building. It uses
`macos-15` for arm64 and `macos-15-intel` for x86_64, then returns to macOS to merge, sign, notarize, and attest
the universal distribution. Missing credentials, multiple Developer ID identities, a non-`Accepted` notarization,
or any checksum mismatch prevents publication. Prerelease tags such as `v0.2.0-rc.1` are marked automatically.

Verify a downloaded release:

```bash
shasum -a 256 -c SHA256SUMS
gh attestation verify awesome-ios-sim-0.2.0-macos-universal.zip \
  -R qubyyang/awesome-ios-sim
unzip -p awesome-ios-sim-0.2.0-macos-universal.zip \
  awesome-ios-sim-0.2.0-macos-universal/bin/ios-sim-state > ios-sim-state
codesign --verify --strict --verbose=2 ios-sim-state
```

Do not retarget or reuse a published version tag. If a release is wrong, publish a new patch version.

## 中文

Release 自动化会分别编译 Apple Silicon 与 Intel Slice，验证两个原生压缩包，再把 CLI 与 MCP Server
合并为一份 Universal ZIP。Tag 发布必须继续通过带 Hardened Runtime 与 Secure Timestamp 的 Developer
ID 签名、Apple `notarytool`、Homebrew Formula 生成、SHA-256 验证和 GitHub 来源证明。Secret 名称与
信任边界见[分发契约](DISTRIBUTION.md)。

准备 Release Commit：

1. 在 `Sources/SimulatorStateCore/Version.swift`、`package.json` 与 `package-lock.json` 中设置目标语义版本。
2. 把相关 CHANGELOG 条目从 `Unreleased` 移到 `## [VERSION] - YYYY-MM-DD`。
3. 运行 `Scripts/release/verify-version.sh`、完整测试，并至少在一种架构上运行
   `Scripts/release/build-artifact.sh`。
4. 提交并推送 Release Preparation Commit。
5. 从该 Commit 手动运行 `Release` 工作流。Release Candidate 必须通过两个原生架构；该次运行只上传
   短期的未签名 Universal 产物并验证 Formula，不读取签名 Secret、不请求 Apple 公证、不生成来源证明，
   也不创建公开 Release。
6. 确认 `DISTRIBUTION.md` 中列出的五个受保护分发 Secret 已配置。
7. 创建并推送带说明的 Tag，例如 `v0.2.0`；Tag 必须指向已审查的 Release Commit。

Tag 触发的工作流会先验证版本与 CHANGELOG，再分别在 `macos-15` arm64 和 `macos-15-intel` x86_64
Runner 上构建，然后回到 macOS 合并、签名、公证并证明 Universal 分发产物。缺少凭据、出现多个
Developer ID 身份、公证结果不是 `Accepted` 或校验和不一致时都会阻止发布。`v0.2.0-rc.1` 之类的
Tag 会自动标记为 Prerelease。

不要移动或重复使用已经发布的版本 Tag；Release 有误时应发布新的补丁版本。
