// 配对令牌生成与持久化。PRD 15.2。
// MVP：单一长期令牌保存在 UserDefaults（二维码配对/一次性配对码在二期）。

import Foundation

enum Pairing {
    private static let tokenKey = "vibecast.pairingToken"

    /// 当前令牌；首次访问时生成并持久化。
    static var token: String {
        if let t = UserDefaults.standard.string(forKey: tokenKey), !t.isEmpty {
            return t
        }
        let t = generate()
        UserDefaults.standard.set(t, forKey: tokenKey)
        return t
    }

    /// 重新生成令牌（撤销旧设备）。
    @discardableResult
    static func regenerate() -> String {
        let t = generate()
        UserDefaults.standard.set(t, forKey: tokenKey)
        return t
    }

    static func validate(_ candidate: String?) -> Bool {
        guard let candidate, !candidate.isEmpty else { return false }
        // 恒定时间比较，避免计时侧信道。
        let a = Array(token.utf8), b = Array(candidate.utf8)
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[i] ^ b[i] }
        return diff == 0
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
