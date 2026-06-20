# 发布规则

每一次对外发布都必须包含人工编写的 Release Notes。

## Release Notes

- 创建或移动 `vX.Y.Z` tag 之前，必须先创建 `docs/releases/X.Y.Z.md`。
- Release Notes 必须覆盖用户可见变化、安装或升级注意事项、已知限制。
- 不允许发布占位内容。
- Release workflow 会把该文件同时用作 GitHub Release 正文和 Sparkle release notes。

## 发布流程

1. 更新 `docs/releases/X.Y.Z.md`。
2. 执行目标版本的发布检查清单。
3. 创建或移动 `vX.Y.Z` tag。
4. 验证 GitHub Release asset 和已发布的 Sparkle appcast。
