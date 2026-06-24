# VibeCast 同步协议 v1

> 前后端唯一对齐来源。Mac (Swift) 与 Web (TypeScript) 双端必须与本文件保持一致。
> 传输层：WebSocket，文本帧，UTF-8 JSON。每条消息一个 JSON 对象，必含 `type` 字段。

---

## 0. 约定

- `protocolVersion`: 当前为 `1`
- `sessionId`: 由手机端生成的 UUID，标识一次「目标编辑会话」。切换目标 = 新会话。
- `targetId`: 目标字符串 ID。动态目标 `current_app` 表示 Mac 当前前台应用；预置目标为 `codex` | `workbuddy` | `notion` | `obsidian` | `codebuddycn` | `codebuddy`；配置页也可创建 `custom_*` 自定义目标。合法字符为字母、数字、`.`、`_`、`-`，长度 2–64。
- `syncMode`: `mirror` 表示完整草稿镜像；`editor` 表示只替换本轮由 VibeCast 插入的文本段，用于 Obsidian、Notion 普通文档块等复杂编辑器。
- `revision`: 每个 targetId 独立维护的单调递增整数，从 `1` 开始。Mac 只应用比已应用版本更高的快照。
- 时间戳 `clientTimestamp`: 毫秒级 Unix 时间（可选，仅诊断用）。
- 图标 `iconDataUrl`: 可选图片 data URL，仅支持 `data:image/...;base64,...`，用于目标卡片和配置页展示。

错误码（`errorCode`）枚举：
`UNPAIRED` · `BAD_TOKEN` · `BAD_MESSAGE` · `UNKNOWN_TARGET` · `APP_NOT_RUNNING` ·
`APP_LAUNCH_FAILED` · `TARGET_NOT_FOCUSED` · `NO_ACCESSIBILITY_PERMISSION` ·
`STALE_REVISION` · `WRITE_FAILED` · `SEND_FAILED` · `SEND_UNKNOWN` · `RATE_LIMITED` ·
`INACTIVE_SESSION`

---

## 1. 握手

### → hello (手机 → Mac)
```json
{
  "type": "hello",
  "protocolVersion": 1,
  "clientId": "android-device-uuid",
  "deviceName": "Android Phone",
  "pairingToken": "secret-token"
}
```

### ← hello_ack (Mac → 手机)
```json
{
  "type": "hello_ack",
  "serverName": "Jeffrey's Mac",
  "protocolVersion": 1,
  "targets": [
    { "id": "current_app", "displayName": "当前应用：Codex", "iconDataUrl": "data:image/png;base64,...", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "codex", "displayName": "Codex", "iconDataUrl": "data:image/png;base64,...", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "workbuddy", "displayName": "WorkBuddy", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "notion", "displayName": "Notion", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "obsidian", "displayName": "Obsidian", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "editor" },
    { "id": "codebuddycn", "displayName": "CodeBuddyCN", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "codebuddy", "displayName": "CodeBuddy", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" }
  ],
  "accessibilityGranted": true,
  "voiceRelayEnabled": false
}
```
> `targets` 只返回已启用且已绑定 Bundle ID 的目标，并可在第一项包含动态 `current_app`。手机端应按该列表动态渲染卡片，而不是写死预置目标。`iconDataUrl` 可省略，手机端应回退到预置图标或首字母图标。`syncMode=editor` 时手机端“发送”按钮显示为“完成”。

### ← targets (Mac → 手机)
当前应用或可用目标变化时，Mac 可主动推送最新目标列表；结构与 `hello_ack.targets` 相同。
```json
{
  "type": "targets",
  "targets": [
    { "id": "current_app", "displayName": "当前应用：Notion", "iconDataUrl": "data:image/png;base64,...", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" },
    { "id": "codex", "displayName": "Codex", "available": true, "clearAfterSend": true, "allowEmpty": false, "syncMode": "mirror" }
  ]
}
```

### ← error (Mac → 手机，握手失败)
```json
{ "type": "error", "errorCode": "BAD_TOKEN", "message": "配对令牌无效" }
```

---

## 2. 选择目标

### → select_target (手机 → Mac)
```json
{ "type": "select_target", "sessionId": "session-uuid", "targetId": "codex" }
```

### ← target_status (Mac → 手机)
`status` 枚举：`focusing` | `focused` | `app_not_running` | `not_focused` | `no_permission` | `error`
```json
{
  "type": "target_status",
  "sessionId": "session-uuid",
  "targetId": "codex",
  "status": "focused",
  "errorCode": null,
  "message": null
}
```
> Mac 在失焦检测后可主动推送 `target_status` (status=not_focused)。

---

## 3. 文本快照

### → text_snapshot (手机 → Mac)
```json
{
  "type": "text_snapshot",
  "sessionId": "session-uuid",
  "targetId": "codex",
  "revision": 23,
  "text": "帮我检查当前分支中的错误。",
  "selectionStart": 13,
  "selectionEnd": 13,
  "isComposing": false,
  "clientTimestamp": 1781760000000
}
```
Mac 规则：
- `revision <= 已应用版本` → 丢弃，回 `text_ack {applied:false, errorCode:"STALE_REVISION"}`
- 目标未聚焦 → 不写入，回 `text_ack {applied:false, errorCode:"TARGET_NOT_FOCUSED"}`
- `isComposing:true` 期间仍可写入预览，但不影响发送门槛
- `syncMode=mirror`：`text` 是完整草稿，Mac 按目标 Profile 做完整镜像。
- `syncMode=editor`：`text` 仍是手机端本轮完整输入，但 Mac 只替换本会话中 VibeCast 插入过的那段文本；若无法读取或设置编辑器选区，必须失败并返回 `WRITE_FAILED`，不得降级为整页全选替换。

### ← text_ack (Mac → 手机)
```json
{
  "type": "text_ack",
  "sessionId": "session-uuid",
  "targetId": "codex",
  "revision": 23,
  "applied": true,
  "errorCode": null,
  "message": null,
  "verified": true
}
```

---

## 4. 两阶段发送

### → send (手机 → Mac)
```json
{ "type": "send", "sessionId": "session-uuid", "targetId": "codex", "revision": 23 }
```
Mac 规则（顺序）：
1. 若 `revision` 尚未应用但手机已发过该快照 → 等待/要求重发；只收到 `<23` 的版本 → 拒绝 (`STALE_REVISION`)
2. 重新校验目标应用 + 输入框焦点
3. 重新校验当前输入内容
4. 执行发送动作（按 Profile：Enter / Cmd+Enter / 自定义），**仅一次**
5. 幂等键 = `sessionId + targetId + revision`，重复 send 不二次提交

### ← send_result (Mac → 手机)
成功：
```json
{ "type": "send_result", "sessionId": "session-uuid", "targetId": "codex", "revision": 23, "success": true }
```
失败：
```json
{
  "type": "send_result",
  "sessionId": "session-uuid",
  "targetId": "codex",
  "revision": 23,
  "success": false,
  "errorCode": "TARGET_NOT_FOCUSED",
  "message": "无法确认 Codex 输入框焦点"
}
```
> 若 Mac 无法判断是否已发送 → `success:false, errorCode:"SEND_UNKNOWN"`，手机不自动重试。

---

## 5. 清空（同步空串，不发送）

### → clear (手机 → Mac)
```json
{ "type": "clear", "sessionId": "session-uuid", "targetId": "codex", "revision": 24 }
```
等价于一次 `text_snapshot{text:""}`，Mac 回 `text_ack`。保持目标与焦点不变。`syncMode=editor` 时只删除本轮由 VibeCast 插入的文本段。

---

## 6. 心跳 / 重连

- 手机每 15s 发 `ping`，Mac 回 `pong`：
```json
{ "type": "ping", "t": 1781760000000 }
{ "type": "pong", "t": 1781760000000 }
```
- 重连后：手机重发 `hello` → `select_target`（恢复上次目标）→ 发送**当前最新完整快照**（不重放历史编辑事件）。

---

## 7. 语音传递

语音传递不是一个配置页中的全局模式，而是一次按住输入框触发的临时会话：
1. 手机端长按目标卡片输入框，发送 `select_target` 并开始采集麦克风 PCM。
2. Mac 切换到目标应用，把默认输入设备临时切到虚拟麦克风，按目标 Profile 的 `voiceShortcut` 唤起系统语音输入法。
3. 手机持续发送音频块；Mac 把音频写入虚拟麦克风对应的输出设备。
4. 手机松手或取消时发送 `voice_stop`；Mac 再按一次 `voiceShortcut` 停止听写，并恢复之前的默认输入设备。

### → voice_start
```json
{
  "type": "voice_start",
  "sessionId": "voice-session-uuid",
  "targetId": "codex",
  "sampleRate": 48000,
  "channels": 1,
  "codec": "pcm_s16le",
  "clientTimestamp": 1781760000000
}
```

当前实验版只接受 `codec="pcm_s16le"`，`sampleRate > 0`，`channels` 为 `1` 或 `2`。

### → voice_chunk
```json
{
  "type": "voice_chunk",
  "sessionId": "voice-session-uuid",
  "targetId": "codex",
  "sequence": 12,
  "audioBase64": "...",
  "clientTimestamp": 1781760000123
}
```

`audioBase64` 是 PCM S16LE 原始字节的 Base64。手机端应等待 `voice_state{state:"started"}` 后发送或刷新缓存的音频块。

### → voice_stop
```json
{
  "type": "voice_stop",
  "sessionId": "voice-session-uuid",
  "targetId": "codex",
  "reason": "release",
  "clientTimestamp": 1781760002500
}
```

`reason` 可为 `release`、`cancel`、`error`、`disconnect`。

### ← voice_state
```json
{
  "type": "voice_state",
  "sessionId": "voice-session-uuid",
  "targetId": "codex",
  "state": "started",
  "message": "语音传递已开始",
  "receivedBytes": 0
}
```

`state` 为 `started`、`stopped` 或 `error`。`receivedBytes` 可省略，停止时用于诊断 Mac 已接收的音频量。

### → get_voice_environment / install_virtual_mic
```json
{ "type": "get_voice_environment" }
{ "type": "install_virtual_mic" }
```

### ← voice_environment
```json
{
  "type": "voice_environment",
  "installed": true,
  "deviceName": "BlackHole 2ch",
  "defaultInputMatches": false,
  "canAutoSwitch": true,
  "message": null
}
```

当前实验版会优先寻找 `VibeCast Virtual Mic`，其次兼容 `BlackHole 2ch`。`install_virtual_mic` 在无内置驱动包时只返回环境诊断，不会静默安装第三方驱动。

`TargetProfile.voiceShortcut`：
```json
{ "voiceShortcut": { "modifiers": [], "key": "right_command" } }
```
默认值为右 Option；闪电说通常使用右 Cmd (`right_command`)。配置页把这个选项放在全局“语音输入环境”里，保存时统一写入各目标 Profile。

---

## 8. 安全校验（Mac 端对每条消息）

必须校验：配对令牌、消息结构合法、targetId 合法、sessionId 与当前绑定一致、revision 单调、text 长度上限（默认 ≤ 10000，可配置）、消息频率（超限回 `RATE_LIMITED`）。

0.1 发布版约束：
- 除 `hello` 外，未完成配对的 WebSocket 消息必须返回 `UNPAIRED`。
- 新配对页面接管控制权后，旧活动绑定失效。
- 配置页连接不接管输入控制权；只有 `select_target`、`text_snapshot`、`clear`、`send` 需要活动输入会话。
- 令牌重新生成后，已配对连接必须断开，旧页面需重新使用新地址。
- 超大文本帧或过大 JSON 消息会被拒绝或关闭连接。

---

## 9. 配置页消息

### → get_config
```json
{ "type": "get_config" }
```

### ← config
```json
{
  "type": "config",
  "targets": [
    {
      "id": "codex",
      "kind": "preset",
      "enabled": true,
      "profile": { "displayName": "Codex", "bundleId": "com.openai.codex", "iconDataUrl": null, "activationMode": "bundle_id" }
    }
  ]
}
```

`kind` 为 `preset` 或 `custom`。预置目标可停用但不可删除；自定义目标可创建、启用、停用和删除。

### → set_config / set_target_enabled / create_target / delete_target
```json
{ "type": "set_config", "targetId": "codex", "profile": { "...": "..." } }
{ "type": "set_target_enabled", "targetId": "codex", "enabled": true }
{ "type": "create_target", "displayName": "TextEdit", "bundleId": "com.apple.TextEdit", "iconDataUrl": "data:image/png;base64,..." }
{ "type": "delete_target", "targetId": "custom_textedit" }
```

### → list_running_apps
```json
{ "type": "list_running_apps" }
```

```json
{
  "type": "running_apps",
  "apps": [
    { "name": "TextEdit", "bundleId": "com.apple.TextEdit", "iconDataUrl": "data:image/png;base64,..." }
  ]
}
```
> `iconDataUrl` 来自 macOS 运行应用或应用包图标；读取失败时可省略。

### → get_status / open_accessibility_settings
```json
{ "type": "get_status" }
{ "type": "open_accessibility_settings" }
```

```json
{ "type": "server_status", "serverName": "Jeffrey's Mac", "accessibilityGranted": true }
```

### → get_network_settings
```json
{ "type": "get_network_settings" }
```

### ← network_settings
```json
{
  "type": "network_settings",
  "settings": { "bindMode": "address", "bindAddress": "192.168.1.12", "port": 8787 },
  "interfaces": [
    { "id": "en0-192.168.1.12", "name": "en0", "address": "192.168.1.12", "isPreferred": true }
  ],
  "portStatus": {
    "bindMode": "address",
    "bindAddress": "192.168.1.12",
    "port": 8787,
    "status": "available",
    "message": "当前服务正在使用"
  },
  "accessUrl": "http://192.168.1.12:8787/?token=..."
}
```

`bindMode` 为 `address` 或 `all`。`all` 表示手机端入口监听全部本地接口 (`0.0.0.0`)，配置页必须在保存前提示公网暴露风险。`accessUrl` 是手机端页面访问地址，不是配置页地址。

### → check_port / ← port_check
```json
{ "type": "check_port", "bindMode": "address", "bindAddress": "192.168.1.12", "port": 8787 }
```

```json
{
  "type": "port_check",
  "result": {
    "bindMode": "address",
    "bindAddress": "192.168.1.12",
    "port": 8787,
    "status": "available",
    "message": "端口可用"
  }
}
```

`status` 为 `available`、`unavailable` 或 `invalid`。当前服务正在使用的配置应返回 `available`，避免把当前监听端口误报为冲突。

### → set_network_settings
```json
{
  "type": "set_network_settings",
  "settings": { "bindMode": "all", "bindAddress": null, "port": 8788 }
}
```

Mac 保存后只重启手机端入口服务。配置页必须保持在 `127.0.0.1` / `localhost` 的本地控制入口，不随手机端绑定 IP 或端口跳转。
