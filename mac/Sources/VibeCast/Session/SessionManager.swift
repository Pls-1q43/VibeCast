// 会话与协议分发。M2：hello 握手 + 令牌校验 + 单一活动会话约束。
// M3：select_target → 应用激活 + 聚焦 + 绑定校验。text_snapshot/send 仍为桩（M4/M5）。

import Foundation

protocol SessionManagerDelegate: AnyObject {
    /// 已配对连接数变化（用于菜单栏显示）。
    func sessionPairedCountChanged(_ count: Int)
    func sessionDidLog(_ line: String)
    /// 配置被更新（菜单栏可刷新目标显示名等）。
    func sessionConfigChanged()
}

extension SessionManagerDelegate {
    func sessionConfigChanged() {}
}

final class SessionManager: ServerDelegate {
    weak var delegate: SessionManagerDelegate?

    private let serverName: String
    /// 是否已授予辅助功能权限（实时通过 AccessibilityPermission 读取，此处仅缓存初值）。
    var accessibilityGranted: Bool

    private let config: TargetConfigStore
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
    private let lock = NSLock()

    init(serverName: String, accessibilityGranted: Bool, config: TargetConfigStore = TargetConfigStore()) {
        self.serverName = serverName
        self.accessibilityGranted = accessibilityGranted
        self.config = config
    }

    // MARK: - ServerDelegate

    func server(_ server: Server, didOpen conn: Connection) {
        delegate?.sessionDidLog("ws open \(conn.id.uuidString.prefix(8))")
    }

    func server(_ server: Server, didReceiveText text: String, from conn: Connection) {
        guard let data = text.data(using: .utf8) else { return }
        let type: String
        do {
            type = try ProtocolCodec.messageType(of: data)
        } catch {
            sendError(conn, code: .badMessage, message: "无法解析消息")
            return
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
        default:
            sendError(conn, code: .badMessage, message: "未知消息类型: \(type)")
        }
    }

    func server(_ server: Server, didClose conn: Connection) {
        lock.lock()
        paired.removeValue(forKey: conn.id)
        if activeControllerId == conn.id { activeControllerId = nil }
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
        lock.unlock()
        delegate?.sessionDidLog("system will sleep: 清空目标绑定")
    }

    /// Mac 唤醒：仅记录；目标重选由手机重连后驱动。
    func handleSystemDidWake() {
        delegate?.sessionDidLog("system did wake: 等待手机重连并重新选目标")
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
        // 单一活动会话（PRD 12.2）：最新完成握手的连接接管控制权。
        // 单用户场景下，用户最后打开/重连的页面即其想操作的会话；
        // 旧连接（可能是残留/已切后台的标签页）让出控制，避免新页面被 RATE_LIMITED 卡死。
        let previousActive = activeControllerId
        activeControllerId = conn.id
        // 接管控制权 → 旧绑定失效，等新会话重新选目标。
        if previousActive != conn.id { activeBinding = nil }
        let count = paired.count
        lock.unlock()

        let targets = TargetId.allCases.map {
            TargetInfo(id: $0, displayName: config.profile($0).displayName, available: true)
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
        // 仅活动控制端可操作目标（单一活动会话）。
        lock.lock(); let isActive = (activeControllerId == conn.id); lock.unlock()
        guard isActive else {
            sendError(conn, code: .rateLimited, message: "非活动会话，暂不可操作")
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

        // 2) 绑定存在且目标匹配？
        guard let binding, binding.targetId == targetId else {
            send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                      revision: revision, applied: false, errorCode: .targetNotFocused))
            return
        }

        // 3) 后台执行绑定校验 + 写入（含 AX/剪贴板，耗时）。
        let prof = self.config.profile(targetId)
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }

            // clipboard_paste 会自行重新激活目标，放宽前台校验（控制端常在另一设备/窗口）。
            let requireFrontmost = (prof.writeMode != .clipboardPaste)
            guard FocusController.validate(binding, requireFrontmost: requireFrontmost) else {
                self.lock.lock(); self.activeBinding = nil; self.lock.unlock()
                self.send(conn, TargetStatusMessage(sessionId: sessionId, targetId: targetId,
                                                    status: .notFocused, errorCode: .targetNotFocused,
                                                    message: "目标失焦"))
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .targetNotFocused))
                return
            }

            let result = TextWriter.write(text, to: binding, writeMode: prof.writeMode,
                                          allowSelectAllReplace: prof.allowSelectAllReplace)
            switch result {
            case .applied(let method):
                self.lock.lock(); self.revisionGate.markApplied(targetId, revision: revision); self.lock.unlock()
                self.delegate?.sessionDidLog("text_applied \(targetId.rawValue) rev=\(revision) \(DiagnosticsLog.textDigest(text)) via=\(method)")
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: true, errorCode: nil))
            case .failed(let m):
                self.delegate?.sessionDidLog("text_write_failed \(targetId.rawValue) rev=\(revision): \(m)")
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .writeFailed))
            }
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

        // 绑定存在且匹配？
        guard let binding, binding.targetId == targetId else {
            send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                         revision: revision, success: false, errorCode: .targetNotFocused,
                                         message: "目标未聚焦"))
            return
        }

        let profile = config.profile(targetId)

        // 第二阶段：后台重新校验绑定 → 执行发送动作。
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }

            guard FocusController.validate(binding) else {
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
                self.lock.lock(); self.sendGate.markCommitted(sessionId: msg.sessionId, targetId: targetId, revision: revision); self.lock.unlock()
                self.delegate?.sessionDidLog("sent \(targetId.rawValue) rev=\(revision) mode=\(profile.sendMode.rawValue)")
                self.send(conn, SendResultMessage(sessionId: msg.sessionId, targetId: targetId,
                                                  revision: revision, success: true, errorCode: nil, message: nil))
            case .skipped(let m):
                // 仅同步模式：视为成功（手机端「发送」实为「完成」，PRD 14.2）。
                self.lock.lock(); self.sendGate.markCommitted(sessionId: msg.sessionId, targetId: targetId, revision: revision); self.lock.unlock()
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
        var dict: [String: TargetProfile] = [:]
        for id in TargetId.allCases { dict[id.rawValue] = config.profile(id) }
        send(conn, ConfigMessage(profiles: dict))
    }

    private func handleSetConfig(_ conn: Connection, data: Data) {
        guard let msg = try? ProtocolCodec.decoder.decode(SetConfigMessage.self, from: data) else {
            sendError(conn, code: .badMessage, message: "set_config 结构错误")
            return
        }
        config.update(msg.targetId, msg.profile)
        delegate?.sessionDidLog("config updated \(msg.targetId.rawValue) bundleId=\(msg.profile.bundleId.isEmpty ? "<empty>" : msg.profile.bundleId)")
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

    // MARK: - 发送辅助

    private func send<T: Encodable>(_ conn: Connection, _ msg: T) {
        guard let data = try? ProtocolCodec.encode(msg), let s = String(data: data, encoding: .utf8) else { return }
        conn.sendText(s)
    }

    private func sendError(_ conn: Connection, code: ErrorCode, message: String) {
        send(conn, ErrorMessage(errorCode: code, message: message))
    }

    var pairedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return paired.count
    }
}
