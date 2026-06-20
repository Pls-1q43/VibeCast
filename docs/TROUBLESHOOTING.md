# 排障指南

## 手机打不开页面

检查：

- Mac 和 Android 手机是否在同一局域网。
- VibeCast 菜单栏是否显示“服务运行中”。
- 手机访问的地址是否来自“复制访问地址（含令牌）”。
- macOS 防火墙或路由器是否阻止局域网设备访问 Mac。
- Mac 局域网 IP 是否变化，变化后需要重新复制地址。

## 页面显示未连接

检查：

- URL 中是否有 `token=...`。
- 是否重新生成过配对令牌。重新生成后旧地址会失效。
- VibeCast 是否仍在运行。
- 手机浏览器是否从后台恢复，必要时刷新页面。

## 提示辅助功能未授权

打开：

```text
系统设置 → 隐私与安全性 → 辅助功能
```

勾选 VibeCast。若已经勾选但仍失败，尝试取消后重新勾选，并重启 VibeCast。

## 目标应用未运行

如果目标配置里 `launchIfNotRunning=false`，VibeCast 不会自动启动目标应用。可以：

- 先手动打开目标应用。
- 或在配置页开启“未运行时启动”。

## 目标失焦或同步失败

常见原因：

- 目标应用被切到后台。
- 输入框焦点被目标应用内部 UI 改变。
- 聚焦快捷键不再有效。
- Electron 或 WebView 控件不支持 AXValue 直写。

处理方式：

1. 在手机端点击“重新聚焦”。
2. 在配置页重新测试目标。
3. 对 Electron/contenteditable 目标尝试 `writeMode=clipboard_paste`。
4. 对高风险页面关闭 `allowSelectAllReplace`。

## 发送失败

发送前 Mac 必须确认最终 revision 已经写入目标输入框。失败时：

- 等待状态变为“已同步”后再发送。
- 确认目标应用仍在前台或可被重新激活。
- 确认 `sendShortcut` 是否符合目标应用发送方式。
- 对 Notion 文本块场景使用 `sendMode=none`。

## Notion 写入范围不对

Notion 普通页面可能包含复杂编辑器和整页焦点。建议：

- 先手动点到目标 AI 输入框或文本块。
- 使用 `focusMode=preserve_last_focus`。
- 使用 `writeMode=clipboard_paste`。
- 保持 `allowSelectAllReplace=false`。
- 先用“测试目标”确认写入范围。

## npm 构建报 preload 错误

如果看到 `genie-safe-delete` 或类似 preload 错误，运行：

```bash
NODE_OPTIONS="" npm run build
NODE_OPTIONS="" npm test
```

## 诊断日志

菜单栏点击“查看日志…”，可以查看最近日志并导出诊断包。日志默认脱敏，不包含完整文本、令牌或剪贴板内容。
