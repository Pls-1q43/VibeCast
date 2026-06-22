// 会话与协议分发：hello 握手、令牌校验、单一活动控制端、目标绑定、
// revision 门控、发送幂等和发布版安全护栏。

import Foundation

protocol SessionManagerDelegate: AnyObject {
    /// 已配对连接数变化（用于菜单栏显示）。
    func sessionPairedCountChanged(_ count: Int)
    func sessionDidLog(_ line: String)
    /// 配置被更新（菜单栏可刷新目标显示名等）。
    func sessionConfigChanged()
    /// 手机端网络入口配置被更新（用于重启手机端服务）。
    func sessionNetworkSettingsChanged(_ settings: NetworkSettings)
}

extension SessionManagerDelegate {
    func sessionConfigChanged() {}
    func sessionNetworkSettingsChanged(_ settings: NetworkSettings) {}
}

final class SessionManager: ServerDelegate {
    weak var delegate: SessionManagerDelegate?

    private let serverName: String
    /// 是否已授予辅助功能权限（实时通过 AccessibilityPermission 读取，此处仅缓存初值）。
    var accessibilityGranted: Bool

    private let config: TargetConfigStore
    private let networkSettings: NetworkSettingsStore
    /// 聚焦/激活在后台串行队列执行（含同步等待，勿阻塞主线程/服务队列）。
    private let focusQueue = DispatchQueue(label: "vibecast.focus")

    /// 已完成 hello 握手的连接。
    private var paired: [UUID: Connection] = [:]
    /// 当前活动控制连接（单一活动会话，PRD 12.2）。
    private var activeControllerId: UUID?
    /// 当前活动目标绑定（仅一个，PRD 12.2）。
    private var activeBinding: TargetBinding?
    /// 每目标已应用的最高 revision（旧版本丢弃，PRD 12.1）。
    private var revisionGate = RevisionGate()
    /// 发送决策与幂等去重（PRD 11.4 / 16.6）。
    private var sendGate = SendGate()
    /// 每连接消息速率限制，避免旧页面/异常客户端刷爆控制通道。
    private var rateLimiters: [UUID: MessageRateLimiter] = [:]
    /// editor 同步模式下，每个会话只替换本轮由 VibeCast 插入的文本段。
    private var editorStates: [EditorSessionKey: EditorInsertionState] = [:]
    private let lock = NSLock()
    private let maxMessageBytes = 128 * 1024

    private struct EditorSessionKey: Hashable {
        let sessionId: String
        let targetId: TargetId
    }

    init(serverName: String, accessibilityGranted: Bool, config: TargetConfigStore = TargetConfigStore(),
         networkSettings: NetworkSettingsStore = NetworkSettingsStore()) {
        self.serverName = serverName
        self.accessibilityGranted = accessibilityGranted
        self.config = config
        self.networkSettings = networkSettings
    }

    // MARK: - ServerDelegate

    func server(_ server: Server, didOpen conn: Connection) {
        delegate?.sessionDidLog("ws open \(conn.id.uuidString.prefix(8))")
    }

    func server(_ server: Server, didReceiveText text: String, from conn: Connection) {
        guard let data = text.data(using: .utf8) else { return }
        guard data.count <= maxMessageBytes else {
            sendError(conn, code: .badMessage, message: "消息过大")
            conn.close()
            return
        }

        let type: String
        do {
            type = try ProtocolCodec.messageType(of: data)
        } catch {
            sendError(conn, code: .badMessage, message: "无法解析消息")
            return
        }

        if type != "hello" {
            guard isPaired(conn) else {
                sendError(conn, code: .unpaired, message: "请先完成配对握手")
                return
            }
            guard allowMessage(from: conn) else {
                sendError(conn, code: .rateLimited, message: "消息过于频繁")
                return
            }
            if SessionManager.requiresActiveController(type), !ensureActive(conn) {
                sendError(conn, code: .inactiveSession, message: "非活动输入会话，请重新选择目标")
                return
            }
        }

        switch type {
        case "hello":
            handleHello(conn, data: data)
        case "ping":
            // 心跳由 Connection 层的 WS ping/pong 兜底；应用层 ping 也回 pong。
            if let ping = try? ProtocolCodec.decoder.decode(PingMessage.self, from: data) {
                send(conn, PongMessage(t: ping.t))
            }
        case "select_target":
            handleSelectTarget(conn, data: data)
        case "text_snapshot":
            handleTextSnapshot(conn, data: data)
        case "clear":
            handleClear(conn, data: data)
        case "send":
            handleSend(conn, data: data)
        case "get_config":
            handleGetConfig(conn)
        case "set_config":
            handleSetConfig(conn, data: data)
        case "test_target":
            handleTestTarget(conn, data: data)
        case "list_running_apps":
            handleListRunningApps(conn)
        case "get_status":
            handleGetStatus(conn)
        case "get_network_settings":
            handleGetNetworkSettings(conn)
        case "set_network_settings":
            handleSetNetworkSettings(conn, data: data)
        case "check_port":
            handleCheckPort(conn, data: data)
        case "open_accessibility_settings":
            handleOpenAccessibilitySettings()
        case "create_target":
            handleCreateTarget(conn, data: data)
        case "delete_target":
            handleDeleteTarget(conn, data: data)
        case "set_target_enabled":
            handleSetTargetEnabled(conn, data: data)
        default:
            sendError(conn, code: .badMessage, message: "未知消息类型: \(type)")
        }
    }

    func server(_ server: Server, didClose conn: Connection) {
        lock.lock()
        paired.removeValue(forKey: conn.id)
        rateLimiters.removeValue(forKey: conn.id)
        if activeControllerId == conn.id {
            activeControllerId = nil
            activeBinding = nil
            editorStates.removeAll()
        }
        let count = paired.count
        lock.unlock()
        delegate?.sessionPairedCountChanged(count)
        delegate?.sessionDidLog("ws close \(conn.id.uuidString.prefix(8))")
    }

    func serverConnectionCountChanged(_ count: Int) {
        // 原始 TCP 连接数变化暂不直接用于 UI（以 paired 计数为准）。
    }

    // MARK: - 系统事件

    /// Mac 进入睡眠：清空活动绑定，使唤醒后必须重新选目标（PRD 16.5）。
    /// 不恢复未完成发送动作。
    func handleSystemWillSleep() {
        lock.lock()
        activeBinding = nil
        editorStates.removeAll()
        lock.unlock()
        delegate?.sessionDidLog("system will sleep: 清空目标绑定")
    }

    /// Mac 唤醒：仅记录；目标重选由手机重连后驱动。
    func handleSystemDidWake() {
        delegate?.sessionDidLog("system did wake: 等待手机重连并重新选目标")
    }

    /// 令牌撤销/轮换后调用：关闭已配对页面，清空活动绑定。
    func revokePairings() {
        lock.lock()
        let conns = Array(paired.values)
        paired.removeAll()
        rateLimiters.removeAll()
        activeControllerId = nil
        activeBinding = nil
        editorStates.removeAll()
        let count = paired.count
        lock.unlock()
        for conn in conns { conn.close() }
        delegate?.sessionPairedCountChanged(count)
        delegate?.sessionDidLog("pairings revoked")
    }

    // MARK: - 消息处理

    private func handleHello(_ conn: Connection, data: Data) {
        guard let hello = try? ProtocolCodec.decoder.decode(HelloMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "hello 结构错误")
            return
        }
        guard hello.protocolVersion == kProtocolVersion else {
            sendError(conn, code: .badMessage, message: "协议版本不匹配")
            return
        }
        guard Pairing.validate(hello.pairingToken) else {
            sendError(conn, code: .badToken, message: "配对令牌无效")
            conn.close()
            return
        }

        lock.lock()
        paired[conn.id] = conn
        rateLimiters[conn.id] = MessageRateLimiter()
        // 单一活动输入会话（PRD 12.2）：最新手机输入页接管控制权。
        // 单用户场景下，用户最后打开/重连的页面即其想操作的会话；
        // 配置页不接管输入控制权，否则会让手机端同步被误判为非活动会话。
        let isConfigPage = hello.deviceName == "Config Page"
        if !isConfigPage {
            let previousActive = activeControllerId
            activeControllerId = conn.id
            // 接管控制权 → 旧绑定失效，等新会话重新选目标。
            if previousActive != conn.id { activeBinding = nil }
        }
        let count = paired.count
        lock.unlock()

        let targets = config.activeTargets.map { entry in
            let profile = profileWithResolvedIcon(entry.profile)
            return TargetInfo(id: entry.id, displayName: profile.displayName, available: true,
                              clearAfterSend: profile.clearAfterSend, allowEmpty: profile.allowEmpty,
                              syncMode: profile.syncMode,
                              iconDataUrl: profile.iconDataUrl)
        }
        send(conn, HelloAckMessage(serverName: serverName,
                                   protocolVersion: kProtocolVersion,
                                   targets: targets,
                                   accessibilityGranted: AccessibilityPermission.isGranted))
        delegate?.sessionPairedCountChanged(count)
        delegate?.sessionDidLog("paired \(hello.deviceName) (\(conn.id.uuidString.prefix(8)))")
    }

    struct TargetedEnvelope: Codable { let sessionId: String; let targetId: TargetId }

    /// 处理目标选择：后台激活+聚焦，记录绑定，回 target_status。PRD 9。
    private func handleSelectTarget(_ conn: Connection, data: Data) {
        guard let env = try? ProtocolCodec.decoder.decode(TargetedEnvelope.self, from: data) else {
            sendError(conn, code: .badMessage, message: "select_target 结构错误")
            return
        }
        guard config.isUsable(env.targetId) else {
            send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                           status: .error, errorCode: .unknownTarget,
                                           message: "目标未启用或尚未配置 Bundle ID"))
            return
        }

        guard AccessibilityPermission.isGranted else {
            send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                           status: .noPermission, errorCode: .noAccessibilityPermission,
                                           message: "Mac 缺少辅助功能权限"))
            return
        }

        // 先回「正在聚焦」，再后台执行（可能耗时数百毫秒）。
        send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                       status: .focusing, errorCode: nil, message: nil))

        let profile = config.profile(env.targetId)
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }
            let outcome = FocusController.focus(targetId: env.targetId, sessionId: env.sessionId, profile: profile)
            let status: TargetStatusMessage
            switch outcome {
            case .focused(let binding):
                // 新会话：重置该目标已应用 revision，使新草稿的 rev 从头生效（PRD 12.3）。
                self.lock.lock()
                self.activeBinding = binding
                self.revisionGate.reset(env.targetId)
                self.editorStates = self.editorStates.filter { $0.key.targetId != env.targetId }
                self.lock.unlock()
                self.delegate?.sessionDidLog("focused \(env.targetId.rawValue) pid=\(binding.pid) role=\(binding.role ?? "?")")
                status = TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                             status: .focused, errorCode: nil, message: nil)
            case .appNotRunning:
                status = TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                             status: .appNotRunning, errorCode: .appNotRunning,
                                             message: "应用未运行")
            case .appLaunchFailed(let m):
                status = TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                             status: .appNotRunning, errorCode: .appLaunchFailed, message: m)
            case .noPermission:
                status = TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                             status: .noPermission, errorCode: .noAccessibilityPermission,
                                             message: "Mac 缺少辅助功能权限")
            case .notFocused(let m):
                status = TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                             status: .notFocused, errorCode: .targetNotFocused, message: m)
            }
            self.send(conn, status)
        }
    }

    /// 处理文本快照写入。PRD 6.3 / 10 / 12.1。
    private func handleTextSnapshot(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(TextSnapshotMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "text_snapshot 结构错误")
            return
        }
        // 文本长度护栏（PRD 15.3）。
        let maxLen = config.profile(msg.targetId).maxTextLength
        if msg.text.count > maxLen {
            send(conn, TextAckMessage(sessionId: msg.sessionId, targetId: msg.targetId,
                                      revision: msg.revision, applied: false, errorCode: .writeFailed))
            return
        }
        applyText(conn, sessionId: msg.sessionId, targetId: msg.targetId,
                  revision: msg.revision, text: msg.text)
    }

    /// 处理清空（同步空串，不发送）。PRD 5.7。
    private func handleClear(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(ClearMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "clear 结构错误")
            return
        }
        applyText(conn, sessionId: msg.sessionId, targetId: msg.targetId,
                  revision: msg.revision, text: "")
    }

    /// 核心写入流程：Revision 校验 → 绑定校验 → TextWriter 写入 → text_ack。
    private func applyText(_ conn: Connection, sessionId: String, targetId: TargetId, revision: Int, text: String) {
        guard config.isUsable(targetId) else {
            send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                      revision: revision, applied: false, errorCode: .unknownTarget,
                                      message: "目标未启用或尚未配置 Bundle ID", verified: false))
            return
        }
        // 1) Revision 单调校验（旧包丢弃，PRD 12.1）。
        lock.lock()
        let shouldApply = revisionGate.shouldApply(targetId, revision: revision)
        let binding = activeBinding
        lock.unlock()

        if !shouldApply {
            send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                      revision: revision, applied: false, errorCode: .staleRevision))
            return
        }

        // 2) 绑定存在，且目标/session 均匹配？
        guard let binding, binding.targetId == targetId, binding.sessionId == sessionId else {
            send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                      revision: revision, applied: false, errorCode: .targetNotFocused,
                                      message: "目标会话已失效", verified: false))
            return
        }

        // 3) 后台执行绑定校验 + 写入（含 AX/剪贴板，耗时）。
        let prof = self.config.profile(targetId)
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }

            self.lock.lock()
            let stillFresh = self.revisionGate.shouldApply(targetId, revision: revision)
            self.lock.unlock()
            guard stillFresh else {
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .staleRevision))
                return
            }

            // 剪贴板写入会自行重新激活目标，放宽前台校验（控制端常在另一设备/窗口）。
            let emptyAutoClearUsesClipboard = text.isEmpty && prof.writeMode == .auto && prof.allowSelectAllReplace
            let requireFrontmost = !(prof.syncMode == .editor || prof.writeMode.usesClipboard || emptyAutoClearUsesClipboard)
            guard FocusController.validate(binding, requireFrontmost: requireFrontmost) else {
                self.lock.lock(); self.activeBinding = nil; self.lock.unlock()
                self.send(conn, TargetStatusMessage(sessionId: sessionId, targetId: targetId,
                                                    status: .notFocused, errorCode: .targetNotFocused,
                                                    message: "目标失焦"))
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .targetNotFocused,
                                               message: "目标失焦", verified: false))
                return
            }

            let method: String
            let verified: Bool
            if prof.syncMode == .editor {
                let key = EditorSessionKey(sessionId: sessionId, targetId: targetId)
                self.lock.lock()
                let editorState = self.editorStates[key]
                self.lock.unlock()
                let allowUndoPasteFallback = targetId == .obsidian || binding.bundleId == "md.obsidian"
                switch TextWriter.writeEditor(text, to: binding, replacing: editorState,
                                              allowUndoPasteFallback: allowUndoPasteFallback) {
                case .applied(let appliedMethod, let nextState):
                    method = appliedMethod
                    verified = false
                    self.lock.lock()
                    if let nextState {
                        self.editorStates[key] = nextState
                    } else {
                        self.editorStates.removeValue(forKey: key)
                    }
                    self.lock.unlock()
                case .failed(let message):
                    self.delegate?.sessionDidLog("text_write_failed \(targetId.rawValue) rev=\(revision): \(message)")
                    self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                                   revision: revision, applied: false, errorCode: .writeFailed,
                                                   message: message, verified: false))
                    return
                }
            } else {
                switch TextWriter.write(text, to: binding, writeMode: prof.writeMode,
                                        allowSelectAllReplace: prof.allowSelectAllReplace) {
                case .applied(let appliedMethod):
                    method = appliedMethod
                    verified = !appliedMethod.contains("unverified")
                case .failed(let message):
                    self.delegate?.sessionDidLog("text_write_failed \(targetId.rawValue) rev=\(revision): \(message)")
                    self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                                   revision: revision, applied: false, errorCode: .writeFailed,
                                                   message: message, verified: false))
                    return
                }
            }

            self.lock.lock(); self.revisionGate.markApplied(targetId, revision: revision); self.lock.unlock()
            self.delegate?.sessionDidLog("text_applied \(targetId.rawValue) rev=\(revision) \(DiagnosticsLog.textDigest(text)) via=\(method)")
            self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                           revision: revision, applied: true, errorCode: nil,
                                           message: nil, verified: verified))
        }
    }

    /// 两阶段发送。PRD 3.3 / 11.4 / 13 / 16.6。
    private func handleSend(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(SendRequestMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "send 结构错误")
            return
        }
        let targetId = msg.targetId
        let revision = msg.revision
        guard config.isUsable(targetId) else {
            send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                         revision: revision, success: false, errorCode: .unknownTarget,
                                         message: "目标未启用或尚未配置 Bundle ID"))
            return
        }

        lock.lock()
        let decision = sendGate.decide(sessionId: msg.sessionId, targetId: targetId,
                                       revision: revision, appliedRevision: revisionGate.current(targetId))
        let binding = activeBinding
        lock.unlock()

        switch decision {
        case .duplicate:
            // 幂等：同一 session+target+revision 不重复提交（PRD 16.6）。
            send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                         revision: revision, success: true, errorCode: nil,
                                         message: "已发送（幂等命中）"))
            return
        case .staleRevision:
            // 第一阶段：最终 revision 尚未写入，拒绝发送（PRD 11.4）。
            send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                         revision: revision, success: false, errorCode: .staleRevision,
                                         message: "最终文本尚未同步完成"))
            return
        case .proceed:
            break
        }

        // 绑定存在，且目标/session 均匹配？
        guard let binding, binding.targetId == targetId, binding.sessionId == msg.sessionId else {
            send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                         revision: revision, success: false, errorCode: .targetNotFocused,
                                         message: "目标会话已失效"))
            return
        }

        let profile = config.profile(targetId)

        // 第二阶段：后台重新校验绑定 → 执行发送动作。
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }

            // 剪贴板写入目标的 SendAction 会自行重新激活，放宽前台校验。
            let requireFrontmost = !(profile.syncMode == .editor || profile.writeMode.usesClipboard)
            guard FocusController.validate(binding, requireFrontmost: requireFrontmost) else {
                self.lock.lock(); self.activeBinding = nil; self.lock.unlock()
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: false, errorCode: .targetNotFocused,
                                                  message: "发送前目标已失焦"))
                return
            }

            let result = SendAction.perform(profile: profile, binding: binding)
            switch result {
            case .sent:
                // 标记幂等键，发送动作只执行一次（PRD 13 / 16.6）。
                self.lock.lock()
                self.sendGate.markCommitted(sessionId: msg.sessionId, targetId: targetId, revision: revision)
                if profile.syncMode == .editor {
                    self.editorStates.removeValue(forKey: EditorSessionKey(sessionId: msg.sessionId, targetId: targetId))
                }
                self.lock.unlock()
                self.delegate?.sessionDidLog("sent \(targetId.rawValue) rev=\(revision) mode=\(profile.sendMode.rawValue)")
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: true, errorCode: nil, message: nil))
            case .skipped(let m):
                // 仅同步模式：视为成功（手机端「发送」实为「完成」，PRD 14.2）。
                self.lock.lock()
                self.sendGate.markCommitted(sessionId: msg.sessionId, targetId: targetId, revision: revision)
                if profile.syncMode == .editor {
                    self.editorStates.removeValue(forKey: EditorSessionKey(sessionId: msg.sessionId, targetId: targetId))
                }
                self.lock.unlock()
                self.delegate?.sessionDidLog("send-skip \(targetId.rawValue): \(m)")
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: true, errorCode: nil, message: m))
            case .unknown(let m):
                // 无法确认是否已发送：不标记幂等、不自动重试（PRD 13）。
                self.delegate?.sessionDidLog("send-unknown \(targetId.rawValue): \(m)")
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: false, errorCode: .sendUnknown, message: m))
            case .failed(let m):
                self.delegate?.sessionDidLog("send-failed \(targetId.rawValue): \(m)")
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: false, errorCode: .sendFailed, message: m))
            }
        }
    }

    // MARK: - 配置读写（PRD 20）

    private func handleGetConfig(_ conn: Connection) {
        send(conn, ConfigMessage(targets: config.allTargets.map {
            ConfigTarget(id: $0.id, kind: $0.kind, enabled: $0.enabled,
                         profile: profileWithResolvedIcon($0.profile))
        }))
    }

    private func handleSetConfig(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(SetConfigMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "set_config 结构错误")
            return
        }
        let profile = msg.profile.normalized()
        guard config.update(msg.targetId, profile) else {
            sendError(conn, code: .unknownTarget, message: "未知目标: \(msg.targetId.rawValue)")
            return
        }
        delegate?.sessionDidLog("config updated \(msg.targetId.rawValue) bundleId=\(profile.bundleId.isEmpty ? "<empty>" : profile.bundleId)")
        // 回写最新全量配置，便于配置页确认。
        handleGetConfig(conn)
        delegate?.sessionConfigChanged()
    }

    /// 测试目标：激活→聚焦→写测试文本→不发送→回结果（PRD 20）。
    private func handleTestTarget(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(TestTargetMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "test_target 结构错误")
            return
        }
        guard config.entry(msg.targetId) != nil else {
            sendError(conn, code: .unknownTarget, message: "未知目标: \(msg.targetId.rawValue)")
            return
        }
        guard AccessibilityPermission.isGranted else {
            send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                         errorCode: .noAccessibilityPermission, message: "Mac 缺少辅助功能权限"))
            return
        }
        let profile = config.profile(msg.targetId)
        let testSessionId = "test-\(UUID().uuidString)"
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }
            let outcome = FocusController.focus(targetId: msg.targetId, sessionId: testSessionId, profile: profile)
            switch outcome {
            case .focused(let binding):
                let result = TextWriter.write("VibeCast 测试文本（不会发送）", to: binding, writeMode: profile.writeMode, allowSelectAllReplace: profile.allowSelectAllReplace)
                switch result {
                case .applied(let method):
                    self.delegate?.sessionDidLog("test_target \(msg.targetId.rawValue) ok via=\(method)")
                    self.send(conn, TestResultMessage(targetId: msg.targetId, success: true,
                                                      errorCode: nil, message: "已写入测试文本（via=\(method)），未执行发送"))
                case .failed(let m):
                    self.send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                                      errorCode: .writeFailed, message: m))
                }
            case .appNotRunning:
                self.send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                                  errorCode: .appNotRunning, message: "应用未运行"))
            case .appLaunchFailed(let m):
                self.send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                                  errorCode: .appLaunchFailed, message: m))
            case .noPermission:
                self.send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                                  errorCode: .noAccessibilityPermission, message: "Mac 缺少辅助功能权限"))
            case .notFocused(let m):
                self.send(conn, TestResultMessage(targetId: msg.targetId, success: false,
                                                  errorCode: .targetNotFocused, message: m))
            }
        }
    }

    /// 列出当前运行的可见应用（供配置页选择 Bundle ID，PRD 8）。
    private func handleListRunningApps(_ conn: Connection) {
        let apps = RunningAppsProvider.visibleApps()
        send(conn, RunningAppsMessage(apps: apps))
    }

    private func handleGetStatus(_ conn: Connection) {
        send(conn, ServerStatusMessage(serverName: serverName,
                                       accessibilityGranted: AccessibilityPermission.isGranted))
    }

    private func handleGetNetworkSettings(_ conn: Connection) {
        sendNetworkSettings(conn)
    }

    private func handleSetNetworkSettings(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(SetNetworkSettingsMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "set_network_settings 结构错误")
            return
        }
        let next = networkSettings.update(msg.settings)
        sendNetworkSettings(conn)
        delegate?.sessionDidLog("network_settings bind=\(next.bindMode.rawValue) host=\(next.bindAddress ?? "*") port=\(next.port)")
        delegate?.sessionNetworkSettingsChanged(next)
    }

    private func handleCheckPort(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(CheckPortMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "check_port 结构错误")
            return
        }
        let settings = NetworkSettings(bindMode: msg.bindMode, bindAddress: msg.bindAddress, port: msg.port)
        send(conn, PortCheckMessage(result: portStatus(for: settings)))
    }

    private func handleOpenAccessibilitySettings() {
        DispatchQueue.main.async {
            AccessibilityPermission.openSettings()
        }
    }

    private func handleCreateTarget(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(CreateTargetMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "create_target 结构错误")
            return
        }
        let entry = config.createCustom(displayName: msg.displayName, bundleId: msg.bundleId,
                                        iconDataUrl: msg.iconDataUrl)
        delegate?.sessionDidLog("config created \(entry.id.rawValue) bundleId=\(entry.profile.bundleId.isEmpty ? "<empty>" : entry.profile.bundleId)")
        handleGetConfig(conn)
        delegate?.sessionConfigChanged()
    }

    private func handleDeleteTarget(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(DeleteTargetMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "delete_target 结构错误")
            return
        }
        guard config.deleteCustom(msg.targetId) else {
            sendError(conn, code: .badMessage, message: "只能删除自定义目标")
            return
        }
        delegate?.sessionDidLog("config deleted \(msg.targetId.rawValue)")
        handleGetConfig(conn)
        delegate?.sessionConfigChanged()
    }

    private func handleSetTargetEnabled(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(SetTargetEnabledMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "set_target_enabled 结构错误")
            return
        }
        guard config.setEnabled(msg.targetId, enabled: msg.enabled) else {
            sendError(conn, code: .unknownTarget, message: "未知目标: \(msg.targetId.rawValue)")
            return
        }
        delegate?.sessionDidLog("config enabled \(msg.targetId.rawValue)=\(msg.enabled)")
        handleGetConfig(conn)
        delegate?.sessionConfigChanged()
    }

    // MARK: - 发送辅助

    private func send<T: Encodable>(_ conn: Connection, _ msg: T) {
        guard let data = try? ProtocolCodec.encode(msg), let s = String(data: data, encoding: .utf8) else { return }
        conn.sendText(s)
    }

    private func sendNetworkSettings(_ conn: Connection) {
        let settings = networkSettings.normalizedForCurrentInterfaces()
        let interfaces = NetworkInfo.localInterfaces()
        send(conn, NetworkSettingsMessage(settings: settings,
                                          interfaces: interfaces,
                                          portStatus: portStatus(for: settings),
                                          accessUrl: accessURL(for: settings)))
    }

    private func portStatus(for settings: NetworkSettings) -> PortCheckResult {
        let normalized = NetworkSettingsStore.normalized(settings)
        let current = networkSettings.normalizedForCurrentInterfaces()
        if normalized == current {
            return PortCheckResult(bindMode: normalized.bindMode, bindAddress: normalized.bindAddress,
                                   port: normalized.port, status: .available, message: "当前服务正在使用")
        }
        return PortAvailability.check(settings: normalized)
    }

    private func accessURL(for settings: NetworkSettings) -> String? {
        let host: String?
        switch settings.bindMode {
        case .all:
            host = NetworkInfo.primaryLANAddress()
        case .address:
            host = settings.bindAddress
        }
        guard let host, !host.isEmpty else { return nil }
        return "http://\(host):\(settings.port)/?token=\(Pairing.token)"
    }

    private func profileWithResolvedIcon(_ profile: TargetProfile) -> TargetProfile {
        guard profile.iconDataUrl == nil else { return profile }
        var p = profile
        p.iconDataUrl = TargetIconProvider.iconDataURL(bundleId: profile.bundleId)
        return p
    }

    private func sendError(_ conn: Connection, code: ErrorCode, message: String) {
        send(conn, ErrorMessage(errorCode: code, message: message))
    }

    private func isPaired(_ conn: Connection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return paired[conn.id] != nil
    }

    private func ensureActive(_ conn: Connection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return activeControllerId == conn.id
    }

    private func allowMessage(from conn: Connection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var limiter = rateLimiters[conn.id] ?? MessageRateLimiter()
        let ok = limiter.allow(nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        rateLimiters[conn.id] = limiter
        return ok
    }

    static func requiresActiveController(_ type: String) -> Bool {
        switch type {
        case "select_target", "text_snapshot", "clear", "send":
            return true
        default:
            return false
        }
    }

    var pairedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return paired.count
    }
}
