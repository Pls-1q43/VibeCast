// 极简 HTTP/1.1 请求解析。仅支持本产品所需：GET 静态资源 + WS 升级。

import Foundation

struct HTTPRequest {
    let method: String
    let path: String       // 不含查询串
    let rawTarget: String  // 含查询串
    let headers: [String: String] // header 名小写
    let headerEndIndex: Int // 请求头结束（含 \r\n\r\n）在缓冲区中的字节位置

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    var isWebSocketUpgrade: Bool {
        (header("upgrade")?.lowercased() == "websocket")
            && (header("connection")?.lowercased().contains("upgrade") ?? false)
    }

    /// 从缓冲区解析一个完整请求头；不足返回 nil。
    static func parse(_ buffer: Data) -> HTTPRequest? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerEnd = range.upperBound
        let headerData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        guard let headerStr = String(data: headerData, encoding: .utf8) else { return nil }

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        let method = parts[0]
        let rawTarget = parts[1]
        let path = String(rawTarget.split(separator: "?", maxSplits: 1).first ?? "")

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        return HTTPRequest(method: method, path: path, rawTarget: rawTarget,
                           headers: headers, headerEndIndex: headerEnd)
    }
}

enum HTTPResponse {
    static func build(status: Int, reason: String, headers: [String: String] = [:], body: Data = Data()) -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        var h = headers
        h["Content-Length"] = String(body.count)
        h["Connection"] = "close"
        // 允许跨源/模块脚本加载（手机端 type=module crossorigin 资源需要）。
        h["Access-Control-Allow-Origin"] = "*"
        // 局域网下禁缓存，避免手机加载到旧版本资源导致空白。
        h["Cache-Control"] = "no-store"
        for (k, v) in h { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        return out
    }

    static func notFound() -> Data {
        build(status: 404, reason: "Not Found",
              headers: ["Content-Type": "text/plain; charset=utf-8"],
              body: Data("Not Found".utf8))
    }

    static func ok(body: Data, contentType: String) -> Data {
        build(status: 200, reason: "OK", headers: ["Content-Type": contentType], body: body)
    }

    static func mimeType(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "ico": return "image/x-icon"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
        }
    }
}
