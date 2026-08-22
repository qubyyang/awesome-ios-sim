# Release process / 发布流程

## English

Release automation produces separate native archives for Apple Silicon and Intel macOS. Each archive contains
the CLI, MCP server, license, bilingual README files, and machine-readable release metadata. GitHub Actions
verifies the complete test suite, publishes SHA-256 checksums, and generates a provenance attestation for each
archive. Code signing, notarization, universal binaries, and Homebrew distribution are intentionally deferred to
the next roadmap stage.

Prepare a release commit:

1. Set the intended semantic version in
   `Sources/SimulatorStateCore/Version.swift`, `package.json`, and `package-lock.json`.
2. Move relevant changelog entries from `Unreleased` to `## [VERSION] - YYYY-MM-DD`.
3. Run `Scripts/release/verify-version.sh`, the full test suite, and
   `Scripts/release/build-artifact.sh` on at least one supported architecture.
4. Commit and push the release preparation.
5. Run the `Release` workflow manually from that commit. This release-candidate run must validate both native
   architectures; it uploads short-lived artifacts but does not attest or publish them.
6. Create and push an annotated tag, for example `v0.1.0`. The tag must point at the reviewed release commit.

The tag-triggered workflow validates version and changelog alignment before building. It uses
`macos-15` for arm64 and `macos-15-intel` for x86_64, then creates the GitHub Release only after both artifacts
and checksums succeed. Prerelease tags such as `v0.2.0-rc.1` are marked as prereleases automatically.

Verify a downloaded release:

```bash
shasum -a 256 -c SHA256SUMS
gh attestation verify awesome-ios-sim-0.1.0-macos-arm64.tar.gz \
  -R qubyyang/awesome-ios-sim
```

Do not retarget or reuse a published version tag. If a release is wrong, publish a new patch version.

## 中文

Release 自动化会分别生成 Apple Silicon 与 Intel macOS 原生压缩包。每个压缩包包含 CLI、MCP Server、
许可证、中英文 README 和机器可读的 Release Metadata。GitHub Actions 会运行完整测试、发布 SHA-256
校验和，并为每个压缩包生成来源证明。代码签名、公证、Universal Binary 和 Homebrew 分发留到下一路线图阶段。

准备 Release Commit：

1. 在 `Sources/SimulatorStateCore/Version.swift`、`package.json` 与 `package-lock.json` 中设置目标语义版本。
2. 把相关 CHANGELOG 条目从 `Unreleased` 移到 `## [VERSION] - YYYY-MM-DD`。
3. 运行 `Scripts/release/verify-version.sh`、完整测试，并至少在一种架构上运行
   `Scripts/release/build-artifact.sh`。
4. 提交并推送 Release Preparation Commit。
5. 从该 Commit 手动运行 `Release` 工作流。Release Candidate 必须通过两个原生架构；该次运行只上传
   短期产物，不生成来源证明，也不创建公开 Release。
6. 创建并推送带说明的 Tag，例如 `v0.1.0`；Tag 必须指向已审查的 Release Commit。

Tag 触发的工作流会先验证版本与 CHANGELOG，再分别在 `macos-15` arm64 和 `macos-15-intel` x86_64
Runner 上构建；只有两份产物与校验和全部成功后才创建 GitHub Release。`v0.2.0-rc.1` 之类的 Tag
会自动标记为 Prerelease。

不要移动或重复使用已经发布的版本 Tag；Release 有误时应发布新的补丁版本。
