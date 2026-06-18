// 辅助功能权限检测。PRD 7.2。

import ApplicationServices
import AppKit

enum AccessibilityPermission {
    /// 是否已授权（不弹窗）。
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// 检测并在未授权时弹出系统授权提示。
    @discardableResult
    static func promptIfNeeded() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 打开「系统设置 → 隐私与安全性 → 辅助功能」。
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
