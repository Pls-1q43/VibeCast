# 目标应用配置

每个目标使用独立 Profile，配置文件位于：
`~/Library/Application Support/VibeCast/targets.json`

推荐通过菜单栏 **打开配置页面…** 在网页里编辑，改完点保存即生效（无需重启）。

## 字段说明

| 字段 | 说明 |
|---|---|
| `displayName` | 卡片显示名称 |
| `bundleId` | 目标应用 Bundle ID（不写死，从运行应用选择或手填） |
| `launchIfNotRunning` | 未运行时是否自动启动 |
| `focusMode` | 聚焦策略：`shortcut`(应用快捷键) / `preserve_last_focus`(恢复上次焦点) / `accessibility` / `custom` |
| `focusShortcut` | 聚焦快捷键，如 `{modifiers:["command"], key:"l"}` |
| `focusWaitMs` | 聚焦后等待毫秒数 |
| `sendMode` | 发送方式：`key` / `custom_shortcut` / `accessibility_button` / `none`(仅同步) |
| `sendShortcut` | 发送快捷键，如 `{modifiers:[], key:"enter"}` |
| `sendButtonTitleContains` | `accessibility_button` 模式下按钮标题包含的文字，如 `发送` |
| `clearAfterSend` | 发送后是否清空手机草稿 |
| `allowEmpty` | 是否允许发送空文本 |
| `keepForeground` | 是否强制保持目标前台 |
| `maxTextLength` | 单次最大文本长度（默认 10000） |
| `allowSelectAllReplace` | 剪贴板降级时是否允许 Cmd+A 全选替换。**Notion 文本块模式必须为 false** |

## 四应用建议

- **Codex / WorkBuddy / CodeBuddy**：`focusMode=shortcut` 配置各自聊天框聚焦快捷键，
  `sendMode=key, sendShortcut=enter`。
- **Notion**：风险较高，默认 `sendMode=none`（仅同步不发送）、`allowSelectAllReplace=false`，
  避免误覆盖整页文档（见 `KNOWN_LIMITS.md`）。
  - **AI 对话模式**：把 `bundleId` 指向 Notion，配置聚焦到 AI 输入框的快捷键，
    可改 `sendMode` 执行 Notion AI 提交。
  - **当前文本块模式**：先在 Notion 手动点好要写入的文本块，`focusMode=preserve_last_focus`，
    手机「发送」实为「完成」（不提交）。

## 测试目标

配置页每个目标有 **测试目标** 按钮：激活应用 → 聚焦输入框 → 写入测试文本 → **不发送** → 返回结果。
用于在正式使用前验证 Bundle ID、聚焦策略是否正确。
