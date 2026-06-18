// 会话与协议分发。M2：hello 握手 + 令牌校验 + 单一活动会话约束。
// M3+：select_target / text_snapshot / send 将在此扩展接入 Accessibility 层。

import Foundation

protocol SessionManagerDelegate: AnyObject {
    /// 已配对连接数变化（用于菜单栏显示）。
    func sessionPairedCountChanged(_ count: Int)
    func sessionDidLog(_ line: String)
}

final class SessionManager: ServerDelegate {
    weak var delegate: SessionManagerDelegate?

    private let serverName: String
    /// 是否已授予辅助功能权限（M3 接入真实检测，M2 先由外部注入）。
    var accessibilityGranted: Bool

    /// 已完成 hello 握手的连接。
    private var paired: [UUID: Connection] = [:]
    /// 当前活动控制连接（单一活动会话，PRD 12.2）。
    private var activeControllerId: UUID?
    private let lock = NSLock()

    init(serverName: String, accessibilityGranted: Bool) {
        self.serverName = serverName
        self.accessibilityGranted = accessibilityGranted
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
        case "select_target", "text_snapshot", "send", "clear":
            // M3+ 实现。M2 阶段先回非聚焦状态，保证前端不卡死。
            handleStubTargeted(conn, type: type, data: data)
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
            TargetInfo(id: $0, displayName: $0.rawValue.capitalized, available: true)
        }
        send(conn, HelloAckMessage(serverName: serverName,
                                   protocolVersion: kProtocolVersion,
                                   targets: targets,
                                   accessibilityGranted: accessibilityGranted))
        delegate?.sessionPairedCountChanged(count)
        delegate?.sessionDidLog("paired \(hello.deviceName) (\(conn.id.uuidString.prefix(8)))")
    }

    /// M2 临时桩：对目标类消息回一个「未聚焦」状态，待 M3 接入真实聚焦。
    private func handleStubTargeted(_ conn: Connection, type: String, data: Data) {
        struct TargetedEnvelope: Codable { let sessionId: String; let targetId: TargetId }
        guard let env = try? ProtocolCodec.decoder.decode(TargetedEnvelope.self, from: data) else {
            sendError(conn, code: .badMessage, message: "\(type) 结构错误")
            return
        }
        // 仅活动控制端可操作目标。
        lock.lock(); let isActive = (activeControllerId == conn.id); lock.unlock()
        guard isActive else {
            sendError(conn, code: .rateLimited, message: "非活动会话，暂不可操作")
            return
        }
        send(conn, TargetStatusMessage(sessionId: env.sessionId, targetId: env.targetId,
                                       status: .focusing, errorCode: nil,
                                       message: "M2 阶段：聚焦能力在 M3 接入"))
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
