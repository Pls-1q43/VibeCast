// 菜单栏 App 主控。PRD 7.3。
// 组装 Server + SessionManager，渲染状态栏菜单：运行状态/地址/连接数/权限/重启/日志/退出。

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, SessionManagerDelegate {
    private var statusItem: NSStatusItem!
    private var server: Server?
    private var session: SessionManager!
    private let defaultPort: UInt16 = 8787

    private var pairedCount = 0
    private var logLines: [String] = []
    private let maxLogLines = 200

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "VC"
        statusItem.button?.toolTip = "VibeCast"

        let serverName = Host.current().localizedName ?? "Mac"
        session = SessionManager(serverName: serverName, accessibilityGranted: accessibilityGranted())
        session.delegate = self

        startServer()
        rebuildMenu()
    }

    // MARK: - Server 生命周期

    private func startServer() {
        guard let staticServer = StaticFileServer() else {
            log("错误：未找到前端资源（Resources/web）")
            return
        }
        let srv = Server(port: defaultPort, staticServer: staticServer)
        srv.delegate = session
        do {
            try srv.start()
            server = srv
            log("服务已启动，端口 \(defaultPort)")
        } catch {
            log("服务启动失败: \(error)")
        }
        rebuildMenu()
    }

    private func restartServer() {
        log("正在重启服务…")
        server?.stop()
        server = nil
        pairedCount = 0
        startServer()
    }

    // MARK: - 权限

    private func accessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    // MARK: - 菜单

    private func rebuildMenu() {
        let menu = NSMenu()

        let running = server != nil
        menu.addItem(makeInfo(running ? "● 服务运行中" : "○ 服务未运行"))

        if let ip = NetworkInfo.primaryLANAddress() {
            let url = "http://\(ip):\(defaultPort)/?token=\(Pairing.token)"
            menu.addItem(makeInfo("手机访问地址："))
            let addr = makeInfo("  \(ip):\(defaultPort)")
            addr.toolTip = url
            menu.addItem(addr)
            let copyItem = NSMenuItem(title: "复制访问地址（含令牌）", action: #selector(copyAddress), keyEquivalent: "")
            copyItem.target = self
            copyItem.representedObject = url
            menu.addItem(copyItem)
        } else {
            menu.addItem(makeInfo("未检测到局域网地址"))
        }

        menu.addItem(makeInfo("已连接手机：\(pairedCount)"))
        menu.addItem(makeInfo(accessibilityGranted() ? "辅助功能：已授权" : "辅助功能：未授权（M3 起需要）"))

        menu.addItem(.separator())

        if !accessibilityGranted() {
            let permItem = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let restartItem = NSMenuItem(title: "重启服务", action: #selector(restart), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let logItem = NSMenuItem(title: "查看日志…", action: #selector(showLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let regenItem = NSMenuItem(title: "重新生成配对令牌", action: #selector(regenToken), keyEquivalent: "")
        regenItem.target = self
        menu.addItem(regenItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 VibeCast", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func makeInfo(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - 菜单动作

    @objc private func copyAddress(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        log("已复制访问地址到剪贴板")
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func restart() {
        restartServer()
    }

    @objc private func regenToken() {
        Pairing.regenerate()
        log("已重新生成配对令牌，旧设备需重新配对")
        rebuildMenu()
    }

    @objc private func showLog() {
        let alert = NSAlert()
        alert.messageText = "VibeCast 诊断日志"
        alert.informativeText = logLines.suffix(40).joined(separator: "\n")
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        server?.stop()
        NSApp.terminate(nil)
    }

    // MARK: - 日志

    private func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(stamp)] \(line)"
        logLines.append(entry)
        if logLines.count > maxLogLines { logLines.removeFirst(logLines.count - maxLogLines) }
        FileHandle.standardError.write(Data((entry + "\n").utf8))
    }

    // MARK: - SessionManagerDelegate

    func sessionPairedCountChanged(_ count: Int) {
        DispatchQueue.main.async {
            self.pairedCount = count
            self.statusItem.button?.title = count > 0 ? "VC●" : "VC"
            self.rebuildMenu()
        }
    }

    func sessionDidLog(_ line: String) {
        DispatchQueue.main.async { self.log(line) }
    }
}
