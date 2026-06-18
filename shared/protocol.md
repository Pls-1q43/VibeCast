# VibeCast 同步协议 v1

> 前后端唯一对齐来源。Mac (Swift) 与 Web (TypeScript) 双端必须与本文件保持一致。
> 传输层：WebSocket，文本帧，UTF-8 JSON。每条消息一个 JSON 对象，必含 `type` 字段。

---

## 0. 约定

- `protocolVersion`: 当前为 `1`
- `sessionId`: 由手机端生成的 UUID，标识一次「目标编辑会话」。切换目标 = 新会话。
- `targetId`: 四个固定值之一 → `codex` | `workbuddy` | `notion` | `codebuddy`
- `revision`: 每个 targetId 独立维护的单调递增整数，从 `1` 开始。Mac 只应用比已应用版本更高的快照。
- 时间戳 `clientTimestamp`: 毫秒级 Unix 时间（可选，仅诊断用）。

错误码（`errorCode`）枚举：
`UNPAIRED` · `BAD_TOKEN` · `BAD_MESSAGE` · `UNKNOWN_TARGET` · `APP_NOT_RUNNING` ·
`APP_LAUNCH_FAILED` · `TARGET_NOT_FOCUSED` · `NO_ACCESSIBILITY_PERMISSION` ·
`STALE_REVISION` · `WRITE_FAILED` · `SEND_FAILED` · `SEND_UNKNOWN` · `RATE_LIMITED`

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
    { "id": "codex", "displayName": "Codex", "available": true },
    { "id": "workbuddy", "displayName": "WorkBuddy", "available": true },
    { "id": "notion", "displayName": "Notion", "available": true },
    { "id": "codebuddy", "displayName": "CodeBuddy", "available": true }
  ],
  "accessibilityGranted": true
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

## 3. 文本快照（完整快照，非增量）

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

### ← text_ack (Mac → 手机)
```json
{
  "type": "text_ack",
  "sessionId": "session-uuid",
  "targetId": "codex",
  "revision": 23,
  "applied": true,
  "errorCode": null
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
等价于一次 `text_snapshot{text:""}`，Mac 回 `text_ack`。保持目标与焦点不变。

---

## 6. 心跳 / 重连

- 手机每 15s 发 `ping`，Mac 回 `pong`：
```json
{ "type": "ping", "t": 1781760000000 }
{ "type": "pong", "t": 1781760000000 }
```
- 重连后：手机重发 `hello` → `select_target`（恢复上次目标）→ 发送**当前最新完整快照**（不重放历史编辑事件）。

---

## 7. 安全校验（Mac 端对每条消息）

必须校验：配对令牌、消息结构合法、targetId 合法、sessionId 存在、revision 单调、text 长度上限（默认 ≤ 10000，可配置）、消息频率（超限回 `RATE_LIMITED`）。
