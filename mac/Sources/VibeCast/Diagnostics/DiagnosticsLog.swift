// 诊断日志。PRD 21。
// 默认不记录：完整文本、配对令牌、剪贴板内容、用户语音、其他应用内容。
// 仅记录：事件、目标 ID、revision、文本长度、文本哈希、同步耗时、错误码。
// 提供导出诊断包（自动脱敏）。

import Foundation
import CryptoKit

final class DiagnosticsLog {
    static let shared = DiagnosticsLog()

    private let queue = DispatchQueue(label: "vibecast.diag")
    private var lines: [String] = []
    private let maxLines = 500
    private let iso = ISO8601DateFormatter()

    private init() {}

    /// 记录一条事件。调用方有责任不传入敏感内容；此处再做一次令牌脱敏兜底。
    func log(_ line: String) {
        let safe = DiagnosticsLog.redact(line)
        let entry = "[\(iso.string(from: Date()))] \(safe)"
        queue.sync {
            lines.append(entry)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        }
        FileHandle.standardError.write(Data((entry + "\n").utf8))
    }

    /// 文本内容摘要：仅长度 + 短哈希，绝不记录原文（PRD 15.4 / 21）。
    static func textDigest(_ text: String) -> String {
        let len = text.count
        let hash = SHA256.hash(data: Data(text.utf8))
        let short = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8)
        return "len=\(len) sha=\(short)"
    }

    /// 兜底脱敏：抹掉疑似 pairingToken 字段值。
    static func redact(_ s: String) -> String {
        // 形如 token=xxx 或 pairingToken: "xxx" 的片段统一替换。
        var out = s
        let patterns = ["pairingToken", "token"]
        for p in patterns {
            // 兼容 token=xxx / token: xxx / "token": "xxx"（键名后可有引号）。
            if let regex = try? NSRegularExpression(pattern: "\(p)\"?\\s*[=:]\\s*\"?[A-Za-z0-9_\\-+/=]+\"?", options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..., in: out)
                out = regex.stringByReplacingMatches(in: out, range: range, withTemplate: "\(p)=<redacted>")
            }
        }
        return out
    }

    func snapshot(maxTail: Int = 200) -> [String] {
        queue.sync { Array(lines.suffix(maxTail)) }
    }

    /// 导出诊断包到临时目录，返回文件 URL。内容已脱敏。
    func export() -> URL? {
        let all = queue.sync { lines.joined(separator: "\n") }
        let header = """
        VibeCast 诊断包
        导出时间: \(iso.string(from: Date()))
        协议版本: \(kProtocolVersion)
        说明: 本日志默认不含完整文本/令牌/剪贴板内容，仅含事件与脱敏摘要。

        """
        let content = header + all + "\n"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeCast-diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
