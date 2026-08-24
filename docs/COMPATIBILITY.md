# Compatibility contract / 兼容性契约

## English

`awesome-ios-sim` is currently pre-1.0. The profile API remains `awesome-ios-sim/v1alpha1`, but releases
follow these rules:

- Patch releases preserve every profile accepted by the previous release in the same API version.
- Additive fields or operations may appear in a minor release. Existing field meanings and safety boundaries
  remain unchanged.
- A breaking profile change requires a new API version such as `v1alpha2`; the old decoder remains available
  for a documented migration window.
- Unknown profile fields are rejected at every managed object level. This catches misspelled safety-sensitive
  settings instead of silently ignoring them.
- CLI and MCP mutations remain dry-run by default and require explicit confirmation.
- Best-effort capabilities never become advertised as exact without a readback implementation and tests.

The checked-in profile and layer JSON Schemas and Swift runtime validation are one contract. Both enforce
non-empty identifiers, known object fields, and the public `simctl status_bar` value ranges. Ordered overlay
semantics and built-in preset meanings are also public behavior. Contract changes must update the schemas,
runtime validation, fixtures, tests, changelog, and both README files together.

Project versions in `Version.swift`, `package.json`, and `package-lock.json` must match. A release tag must match
that version exactly and have a corresponding changelog section.

## 中文

`awesome-ios-sim` 当前仍处于 1.0 之前，Profile API 为 `awesome-ios-sim/v1alpha1`，发布遵循以下规则：

- 同一 API 版本内，补丁版本必须继续接受上一版本已经接受的 Profile。
- 次版本可以增加字段或操作，但不会改变已有字段含义与安全边界。
- 破坏性 Profile 变更必须升级到新的 API 版本，例如 `v1alpha2`，并为旧版本保留有文档说明的迁移窗口。
- 每一层托管对象都会拒绝未知字段，避免拼错安全敏感配置后被静默忽略。
- CLI 与 MCP 的修改操作继续默认 dry-run，只有显式确认才执行。
- 没有读回实现和测试时，best-effort 能力不会被标记成 exact。

仓库内 Profile/Layer JSON Schema 与 Swift Runtime 校验共同组成一份契约：两者都会检查非空标识符、
已知字段和公开 `simctl status_bar` 参数范围。有序 Overlay 的语义与内置 Preset 的含义也属于公开行为。
任何契约变更都必须同步更新 Schema、Runtime 校验、Fixture、测试、CHANGELOG 与中英文 README。

`Version.swift`、`package.json` 和 `package-lock.json` 的版本必须一致；Release Tag 必须与版本完全匹配，
并在 CHANGELOG 中存在对应章节。
