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
        case "text_snapshot", "send", "clear":
            // 文本写入/发送在 M4/M5 接入。M3 阶段：校验绑定后回当前聚焦状态，不写文本。
            handleTextStub(conn, type: type, data: data)
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
                self.lock.lock(); self.activeBinding = binding; self.lock.unlock()
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

    /// M3 桩：文本/发送暂不写入；先校验当前绑定是否仍有效，给前端真实反馈。
    private func handleTextStub(_ conn: Connection, type: String, data: Data) {
        guard let env = try? ProtocolCodec.decoder.decode(TargetedEnvelope.self, from: data) else {
            sendError(conn, code: .badMessage, message: "\(type) 结构错误")
            return
        }
        lock.lock(); let binding = activeBinding; lock.unlock()
        guard let binding, binding.targetId == env.targetId else {
            send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                           status: .notFocused, errorCode: .targetNotFocused,
                                           message: "目标未聚焦"))
            return
        }
        // 后台校验绑定（含 AX 查询）。
        focusQueue.async { [weak self, weak conn] in
            guard let self, let conn else { return }
            if FocusController.validate(binding) {
                // M4 将在此写入文本；M3 仅确认聚焦仍有效。
                self.delegate?.sessionDidLog("\(type) binding-valid \(env.targetId.rawValue) (M4 写入待接入)")
            } else {
                self.lock.lock(); self.activeBinding = nil; self.lock.unlock()
                self.send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                                    status: .notFocused, errorCode: .targetNotFocused,
                                                    message: "目标失焦"))
            }
        }
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
