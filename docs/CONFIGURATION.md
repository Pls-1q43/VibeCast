# 目标应用配置

VibeCast 使用目标 Profile 管理 App 的激活、聚焦、写入和发送行为。Codex、WorkBuddy、Notion、CodeBuddy 是预置目标；配置页也可以添加任意自定义 App。

配置文件位于：

```text
~/Library/Application Support/VibeCast/targets.json
```

推荐通过菜单栏“打开配置页面…”编辑。保存后立即生效，无需重启 App。

## 配置流程

1. 打开 VibeCast 配置页，按顶部“首次安装清单”检查连接和辅助功能权限。
2. 勾选需要在手机端显示的预置目标；不需要的目标可停用。
3. 在“快速选择”里选择运行中的应用，自动填入 Bundle ID。
4. 如需更多目标，在“添加自定义 App”中从运行应用选择或手动填写名称与 Bundle ID。
5. 保存，并逐个点击“测试”，确认 VibeCast 能写入“VibeCast 测试文本（不会发送）”。
6. 不确定发送行为时，先在高级设置中选择 `sendMode=none`，测试写入范围后再启用发送。

## 字段说明

| 字段 | 说明 |
|---|---|
| `displayName` | 手机卡片显示名称 |
| `bundleId` | macOS 应用 Bundle ID |
| `launchIfNotRunning` | 目标未运行时是否尝试启动 |
| `focusMode` | 聚焦策略：`shortcut`、`preserve_last_focus`、`accessibility`、`custom` |
| `focusShortcut` | 聚焦快捷键，如 `{ "modifiers": ["command"], "key": "l" }` |
| `focusWaitMs` | 执行聚焦动作后的等待时间 |
| `writeMode` | 写入策略：`auto`、`axvalue`、`clipboard_paste` |
| `allowSelectAllReplace` | `auto` 降级时是否允许全选替换 |
| `sendMode` | 发送策略：`key`、`custom_shortcut`、`accessibility_button`、`none` |
| `sendShortcut` | 发送快捷键，如 Enter 或 Cmd+Enter |
| `sendButtonTitleContains` | `accessibility_button` 模式下匹配按钮标题 |
| `clearAfterSend` | 发送成功后清空手机草稿的配置字段；当前版本以手机端实际行为为准 |
| `allowEmpty` | 是否允许发送空文本 |
| `keepForeground` | 是否强制保持目标前台 |
| `maxTextLength` | 单次文本最大长度，默认 10000 |

## 目标列表

| 类型 | 行为 |
|---|---|
| 预置目标 | 默认存在；可启用/停用；不可删除 |
| 自定义目标 | 通过配置页添加；可启用/停用/删除；保存后会出现在手机端输入页面 |

手机端只显示“已启用且已绑定 Bundle ID”的目标。仅启用但未绑定 Bundle ID 的目标会保留在配置页，不会出现在手机端卡片列表中。

## 聚焦策略

| 策略 | 适用场景 |
|---|---|
| `shortcut` | 目标应用有稳定快捷键可聚焦输入框，如聊天框、命令框 |
| `preserve_last_focus` | 目标应用已经手动点好输入框，VibeCast 只恢复当前焦点 |
| `accessibility` | 预留给更自动化的 AX 查找能力，当前实现回退为保留焦点 |
| `custom` | 预留给未来自定义聚焦动作，当前实现回退为保留焦点 |

## 写入策略

| 策略 | 行为 | 适用场景 |
|---|---|---|
| `auto` | 优先 AXValue 直写，失败后按 `allowSelectAllReplace` 决定是否剪贴板替换 | 原生输入框优先 |
| `axvalue` | 只允许 AXValue 直写，失败即拒绝 | 需要最保守写入的目标 |
| `clipboard_replace` | 激活目标后 Cmd+A 全选并粘贴；必须开启 `allowSelectAllReplace` | 已通过测试确认全选只作用于目标输入框 |
| `clipboard_insert` | 激活目标后直接粘贴到当前光标，不全选 | 临时插入文本；不保证完整镜像替换 |
| `clipboard_paste` | 旧配置名，保存后迁移为 `clipboard_replace` | 兼容旧配置 |

剪贴板写入会备份并恢复系统剪贴板。任何会触发 Cmd+A 的路径都必须显式允许全选替换；否则 VibeCast 会拒绝写入，避免误覆盖文档页面。

## 发送策略

| 策略 | 行为 |
|---|---|
| `key` | 使用 `sendShortcut`，默认 Enter |
| `custom_shortcut` | 使用自定义快捷键 |
| `accessibility_button` | 查找标题包含指定文字的按钮并点击 |
| `none` | 仅同步文本，不执行发送 |

VibeCast 的发送是两阶段的：手机点击发送后，Mac 必须确认对应 revision 已写入目标输入框，才会执行发送动作。重复发送同一个 `sessionId + targetId + revision` 不会重复提交。

## 推荐配置

| 目标 | 建议 |
|---|---|
| Codex / WorkBuddy / CodeBuddy | `focusMode=shortcut`，配置聊天框聚焦快捷键；`writeMode=auto`；`sendMode=key`；`sendShortcut=enter` |
| TextEdit / 原生输入框 | `focusMode=preserve_last_focus` 或稳定快捷键；`writeMode=auto`；先用 `sendMode=none` 测试 |
| Electron / WebView 输入框 | 优先测试 `clipboard_replace`；必须确认全选只作用于输入框 |
| Notion AI 输入框 | `focusMode=preserve_last_focus`；`writeMode=clipboard_replace`；`sendMode=key`；`sendShortcut=enter`；`allowSelectAllReplace=true` |
| Notion 当前文本块 | `focusMode=preserve_last_focus`；`writeMode=axvalue` 或 `clipboard_insert`；`sendMode=none`；`allowSelectAllReplace=false` |

VibeCast 以通用可配置目标为核心能力。对任何普通文档页面，不建议开启全选替换。使用前务必通过“测试目标”确认写入范围。
