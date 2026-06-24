// 单个 TCP 连接：先读 HTTP 请求，按路由分流为静态响应或 WebSocket 升级。
// 升级后进入 WS 帧循环，文本帧上抛给 delegate。

import Foundation
import Network

protocol ConnectionDelegate: AnyObject {
    /// WebSocket 握手完成。
    func connectionDidOpenWebSocket(_ conn: Connection)
    /// 收到一条完整文本消息（已解 mask、UTF-8）。
    func connection(_ conn: Connection, didReceiveText text: String)
    /// 连接关闭。
    func connectionDidClose(_ conn: Connection)
}

final class Connection {
    let id = UUID()
    weak var delegate: ConnectionDelegate?

    private let nw: NWConnection
    private let queue: DispatchQueue
    private let staticServer: StaticFileServer
    private let routeMode: StaticFileServer.RouteMode
    private var buffer = Data()
    private var isWebSocket = false
    private var closed = false
    private let maxTextFrameBytes = 128 * 1024

    init(_ nw: NWConnection, staticServer: StaticFileServer, routeMode: StaticFileServer.RouteMode, queue: DispatchQueue) {
        self.nw = nw
        self.staticServer = staticServer
        self.routeMode = routeMode
        self.queue = queue
    }

    func start() {
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.handleClose()
            default:
                break
            }
        }
        nw.start(queue: queue)
        receive()
    }

    private func receive() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.process()
            }
            if isComplete || error != nil {
                self.handleClose()
                return
            }
            if !self.closed { self.receive() }
        }
    }

    private func process() {
        if isWebSocket {
            processWebSocketFrames()
        } else {
            processHTTP()
        }
    }

    // MARK: - HTTP 阶段

    private func processHTTP() {
        guard let req = HTTPRequest.parse(buffer) else { return } // 头未收全，等更多数据

        if req.method == "GET" && req.path == "/ws" && req.isWebSocketUpgrade {
            upgradeToWebSocket(req)
            return
        }

        if req.method == "GET" {
            if let (data, mime) = staticServer.resolve(path: req.path, mode: routeMode) {
                sendRaw(HTTPResponse.ok(body: data, contentType: mime), thenClose: true)
            } else {
                sendRaw(HTTPResponse.notFound(), thenClose: true)
            }
        } else {
            sendRaw(HTTPResponse.build(status: 405, reason: "Method Not Allowed"), thenClose: true)
        }
        buffer.removeAll()
    }

    private func upgradeToWebSocket(_ req: HTTPRequest) {
        guard let key = req.header("sec-websocket-key") else {
            sendRaw(HTTPResponse.build(status: 400, reason: "Bad Request"), thenClose: true)
            return
        }
        let accept = WebSocketCodec.acceptKey(for: key)
        let resp = "HTTP/1.1 101 Switching Protocols\r\n"
            + "Upgrade: websocket\r\n"
            + "Connection: Upgrade\r\n"
            + "Sec-WebSocket-Accept: \(accept)\r\n\r\n"
        // 移除已消费的 HTTP 头，保留可能粘连的后续 WS 帧字节。
        buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: req.headerEndIndex))
        isWebSocket = true
        sendRaw(Data(resp.utf8), thenClose: false)
        delegate?.connectionDidOpenWebSocket(self)
        if !buffer.isEmpty { processWebSocketFrames() }
    }

    // MARK: - WebSocket 阶段

    private func processWebSocketFrames() {
        while !closed {
            switch WebSocketCodec.decode(buffer) {
            case .incomplete:
                return
            case .error:
                close()
                return
            case .frame(let frame, let consumed):
                buffer.removeSubrange(buffer.startIndex..<buffer.index(buffer.startIndex, offsetBy: consumed))
                handleFrame(frame)
            }
        }
    }

    private func handleFrame(_ frame: WSFrame) {
        switch frame.opcode {
        case .text:
            guard frame.payload.count <= maxTextFrameBytes else {
                close()
                return
            }
            if let s = String(data: frame.payload, encoding: .utf8) {
                delegate?.connection(self, didReceiveText: s)
            }
        case .ping:
            sendRaw(WebSocketCodec.encode(opcode: .pong, payload: frame.payload), thenClose: false)
        case .close:
            sendRaw(WebSocketCodec.encodeClose(), thenClose: true)
        case .pong, .binary, .continuation:
            break
        }
    }

    // MARK: - 发送

    /// 发送一条文本 WS 消息。
    func sendText(_ s: String) {
        guard isWebSocket, !closed else { return }
        sendRaw(WebSocketCodec.encodeText(s), thenClose: false)
    }

    private func sendRaw(_ data: Data, thenClose: Bool) {
        nw.send(content: data, completion: .contentProcessed { [weak self] _ in
            if thenClose { self?.close() }
        })
    }

    func close() {
        guard !closed else { return }
        nw.cancel()
        handleClose()
    }

    private func handleClose() {
        guard !closed else { return }
        closed = true
        delegate?.connectionDidClose(self)
    }
}
