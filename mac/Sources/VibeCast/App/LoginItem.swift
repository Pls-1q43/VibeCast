// 登录后自动启动（PRD 7.4）。使用 SMAppService（macOS 13+）。

import ServiceManagement
import Foundation

enum LoginItem {
    /// 是否已注册为登录项。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 开启开机自启。
    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            FileHandle.standardError.write(Data("登录项注册失败: \(error)\n".utf8))
            return false
        }
    }

    /// 关闭开机自启。
    @discardableResult
    static func disable() -> Bool {
        do {
            try SMAppService.mainApp.unregister()
            return true
        } catch {
            FileHandle.standardError.write(Data("登录项注销失败: \(error)\n".utf8))
            return false
        }
    }

    static func toggle() {
        if isEnabled { disable() } else { enable() }
    }
}
