// 局域网 HTTP + WebSocket 服务（NWListener / TCP）。PRD 7.1 / 15.1。
// 仅监听局域网（绑定所有接口，但不做公网转发；外部暴露由用户网络环境决定）。

import Foundation
import Network

protocol ServerDelegate: AnyObject {
    func server(_ server: Server, didOpen conn: Connection)
    func server(_ server: Server, didReceiveText text: String, from conn: Connection)
    func server(_ server: Server, didClose conn: Connection)
    func serverConnectionCountChanged(_ count: Int)
}

final class Server: ConnectionDelegate {
    weak var delegate: ServerDelegate?

    let port: UInt16
    private let queue = DispatchQueue(label: "vibecast.server", attributes: .concurrent)
    private var listener: NWListener?
    private let staticServer: StaticFileServer
    private var connections: [UUID: Connection] = [:]
    private let lock = NSLock()

    init(port: UInt16, staticServer: StaticFileServer) {
        self.port = port
        self.staticServer = staticServer
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] nw in
            self?.accept(nw)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                FileHandle.standardError.write(Data("Listener failed: \(err)\n".utf8))
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        lock.lock()
        let conns = Array(connections.values)
        connections.removeAll()
        lock.unlock()
        for c in conns { c.close() }
        delegate?.serverConnectionCountChanged(0)
    }

    private func accept(_ nw: NWConnection) {
        let conn = Connection(nw, staticServer: staticServer, queue: queue)
        conn.delegate = self
        lock.lock()
        connections[conn.id] = conn
        lock.unlock()
        conn.start()
    }

    var wsConnectionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return connections.count
    }

    // MARK: - ConnectionDelegate

    func connectionDidOpenWebSocket(_ conn: Connection) {
        delegate?.server(self, didOpen: conn)
        delegate?.serverConnectionCountChanged(wsConnectionCount)
    }

    func connection(_ conn: Connection, didReceiveText text: String) {
        delegate?.server(self, didReceiveText: text, from: conn)
    }

    func connectionDidClose(_ conn: Connection) {
        lock.lock()
        connections.removeValue(forKey: conn.id)
        lock.unlock()
        delegate?.server(self, didClose: conn)
        delegate?.serverConnectionCountChanged(wsConnectionCount)
    }
}
