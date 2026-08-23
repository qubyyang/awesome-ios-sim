# Signed distribution and Homebrew / 签名分发与 Homebrew

## English

The release pipeline keeps native compilation, universal packaging, signing, notarization, and publication as
separate gates:

```text
arm64 build + x86_64 build -> checksum verification -> lipo universal archive
    -> Developer ID + hardened runtime + secure timestamp -> Apple notarytool
    -> Homebrew Formula bound to archive SHA-256 -> GitHub artifact attestation -> Release
```

Manual `Release` workflow runs are release candidates. They build both native archives, merge the two Mach-O
slices, validate the universal CLI and MCP server, and render the Formula without reading signing secrets or
contacting Apple's notary service. The resulting metadata states `unsigned-release-candidate` and no GitHub
Release is created.

Tagged runs are fail-closed. They require all five repository secrets before packaging:

| Secret | Content |
| --- | --- |
| `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12`. |
| `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_NOTARY_KEY_BASE64` | Base64-encoded App Store Connect API private key (`.p8`). |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID. |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID. |

The runner creates a temporary keychain with a random password, accepts exactly one `Developer ID Application`
identity, signs each executable separately with hardened runtime and a secure timestamp, and deletes certificate
and key files in an `always()` cleanup step. `notarytool` must return `Accepted`; its submission result and the
exact archive digest are published as a separate JSON asset.

Encode and configure credentials without committing them:

```bash
base64 -i DeveloperIDApplication.p12 | gh secret set MACOS_DEVELOPER_ID_CERTIFICATE_BASE64
gh secret set MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD
base64 -i AuthKey_ABC123XYZ.p8 | gh secret set APPLE_NOTARY_KEY_BASE64
gh secret set APPLE_NOTARY_KEY_ID
gh secret set APPLE_NOTARY_ISSUER_ID
```

For local distribution testing, place both native archives and their `.sha256` files in one directory, then run:

```bash
AISS_NATIVE_ASSETS_DIR=/absolute/path/native-assets \
AISS_DIST_DIR=/absolute/path/distribution \
AISS_CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
AISS_REQUIRE_SIGNING=true \
Scripts/release/build-universal-artifact.sh
```

Submit the exact ZIP with `Scripts/release/notarize-artifact.sh`; its required environment variables are
`AISS_NOTARY_KEY_PATH`, `AISS_NOTARY_KEY_ID`, and `AISS_NOTARY_ISSUER_ID`.

The repository is also a Homebrew tap. The current `v0.1.0` Formula selects the matching native archive and
verifies its SHA-256. Future signed tags publish a generated Formula for the notarized universal archive.

```bash
brew tap qubyyang/awesome-ios-sim https://github.com/qubyyang/awesome-ios-sim
brew install qubyyang/awesome-ios-sim/awesome-ios-sim
```

## 中文

Release 流水线把原生编译、Universal 组装、签名、公证和发布拆成独立门禁：

```text
arm64 构建 + x86_64 构建 -> 校验和验证 -> lipo Universal 压缩包
    -> Developer ID + Hardened Runtime + Secure Timestamp -> Apple notarytool
    -> 绑定压缩包 SHA-256 的 Homebrew Formula -> GitHub 来源证明 -> Release
```

手动运行 `Release` 工作流时属于 Release Candidate：它会构建两个原生压缩包，合并 Mach-O Slice，
验证 Universal CLI 与 MCP Server，并生成 Formula；整个过程不会读取签名 Secret，也不会请求 Apple
公证服务。产物 metadata 会明确记录 `unsigned-release-candidate`，且不会创建 GitHub Release。

Tag 运行采用 fail-closed 策略。组装发布包前必须存在上述五个仓库 Secret。Runner 会创建带随机密码的
临时 Keychain，只接受唯一的 `Developer ID Application` 身份，分别使用 Hardened Runtime 与 Secure
Timestamp 签名两个可执行文件，并在 `always()` 清理步骤删除证书与 API Key。只有 `notarytool` 返回
`Accepted` 才能继续；提交结果及压缩包精确摘要会作为独立 JSON 资产发布。

请使用上面的命令配置 Secret，不要把 `.p12`、密码或 `.p8` 提交到仓库。本地签名测试使用同一
`build-universal-artifact.sh`；公证时为 `notarize-artifact.sh` 设置 `AISS_NOTARY_KEY_PATH`、
`AISS_NOTARY_KEY_ID` 和 `AISS_NOTARY_ISSUER_ID`。

本仓库同时可以作为 Homebrew Tap。当前 `v0.1.0` Formula 会按机器架构选择对应原生压缩包并验证
SHA-256；后续签名 Tag 会为已公证的 Universal 压缩包生成 Formula。

```bash
brew tap qubyyang/awesome-ios-sim https://github.com/qubyyang/awesome-ios-sim
brew install qubyyang/awesome-ios-sim/awesome-ios-sim
```
