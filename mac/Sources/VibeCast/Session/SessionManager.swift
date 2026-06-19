// 会话与协议分发。M2：hello 握手 + 令牌校验 + 单一活动会话约束。
// M3：select_target → 应用激活 + 聚焦 + 绑定校验。text_snapshot/send 仍为桩（M4/M5）。

import Foundation

protocol SessionManagerDelegate: AnyObject {
    /// 已配对连接数变化（用于菜单栏显示）。
    func sessionPairedCountChanged(_ count: Int)
    func sessionDidLog(_ line: String)
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
            // 两阶段发送在 M5 接入；M4 阶段先确保最终快照已写入。
            handleSendStub(conn, data: data)
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
        // 单一活动会话：首个配对连接成为活动控制端。
        if activeControllerId == nil { activeControllerId = conn.id }
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
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }

            guard FocusController.validate(binding) else {
                self.lock.lock(); self.activeBinding = nil; self.lock.unlock()
                self.send(conn, TargetStatusMessage(sessionId: sessionId, targetId: targetId,
                                                    status: .notFocused, errorCode: .targetNotFocused,
                                                    message: "目标失焦"))
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .targetNotFocused))
                return
            }

            let result = TextWriter.write(text, to: binding)
            switch result {
            case .applied(let method):
                self.lock.lock(); self.revisionGate.markApplied(targetId, revision: revision); self.lock.unlock()
                self.delegate?.sessionDidLog("text_applied \(targetId.rawValue) rev=\(revision) len=\(text.count) via=\(method)")
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: true, errorCode: nil))
            case .failed(let m):
                self.delegate?.sessionDidLog("text_write_failed \(targetId.rawValue) rev=\(revision): \(m)")
                self.send(conn, TextAckMessage(sessionId: sessionId, targetId: targetId,
                                               revision: revision, applied: false, errorCode: .writeFailed))
            }
        }
    }

    /// M4 桩：发送先把最终快照写入；提交动作在 M5 接入。
    private func handleSendStub(_ conn: Connection, data: Data) {
        guard let env = try? ProtocolCodec.decoder.decode(TargetedEnvelope.self, from: data) else {
            sendError(conn, code: .badMessage, message: "send 结构错误")
            return
        }
        // M5 将实现：确认 revision 已应用 → 重新校验 → 执行发送动作 → send_result。
        self.delegate?.sessionDidLog("send received \(env.targetId.rawValue) (M5 提交待接入)")
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
