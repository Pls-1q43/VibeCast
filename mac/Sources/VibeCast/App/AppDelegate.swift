// 菜单栏 App 主控。PRD 7.3。
// 组装 Server + SessionManager，渲染状态栏菜单：运行状态/地址/连接数/权限/重启/日志/退出。

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, SessionManagerDelegate {
    private var statusItem: NSStatusItem!
    private var server: Server?
    private var session: SessionManager!
    private let defaultPort: UInt16 = 8787

    private var pairedCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()

        let serverName = Host.current().localizedName ?? "Mac"
        session = SessionManager(serverName: serverName, accessibilityGranted: accessibilityGranted())
        session.delegate = self

        // 首次启动：若未授权辅助功能，弹出系统授权提示（PRD 7.2）。
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.promptIfNeeded()
        }

        startServer()
        rebuildMenu()

        // 权限可能在运行中被授予，菜单周期性刷新权限状态。
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.rebuildMenu()
        }

        registerSleepWakeObservers()
    }

    // MARK: - 睡眠/唤醒（PRD 16.5）

    private func registerSleepWakeObservers() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(systemWillSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(systemDidWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep() {
        session.handleSystemWillSleep()
    }

    @objc private func systemDidWake() {
        session.handleSystemDidWake()
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
        AccessibilityPermission.isGranted
    }

    // MARK: - 菜单

    private func rebuildMenu() {
        updateStatusButton()

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
        menu.addItem(makeInfo(accessibilityGranted() ? "辅助功能：当前运行版本已授权" : "辅助功能：当前运行版本未授权"))

        menu.addItem(.separator())

        if !accessibilityGranted() {
            let permItem = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let configItem = NSMenuItem(title: "打开配置页面…", action: #selector(openConfigPage), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        let restartItem = NSMenuItem(title: "重启服务", action: #selector(restart), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let logItem = NSMenuItem(title: "查看日志…", action: #selector(showLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let regenItem = NSMenuItem(title: "重新生成配对令牌", action: #selector(regenToken), keyEquivalent: "")
        regenItem.target = self
        menu.addItem(regenItem)

        let loginItem = NSMenuItem(title: "登录时自动启动", action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

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

    private func configureStatusItem() {
        statusItem.length = NSStatusItem.squareLength
        updateStatusButton()
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.toolTip = pairedCount > 0 ? "VibeCast · 已连接 \(pairedCount) 台设备" : "VibeCast"
        button.imagePosition = .imageOnly

        if let image = statusBarIcon() {
            button.title = ""
            button.image = image
        } else {
            button.image = nil
            button.title = pairedCount > 0 ? "VC●" : "VC"
        }
    }

    private func statusBarIcon() -> NSImage? {
        let urls = [
            Bundle.main.url(forResource: "StatusBarIconTemplate", withExtension: "png"),
            Bundle.module.url(forResource: "StatusBarIconTemplate", withExtension: "png")
        ].compactMap { $0 }

        for url in urls {
            if let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    // MARK: - 菜单动作

    @objc private func copyAddress(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        log("已复制访问地址到剪贴板")
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func restart() {
        restartServer()
    }

    @objc private func regenToken() {
        Pairing.regenerate()
        session.revokePairings()
        log("已重新生成配对令牌，旧设备需重新配对")
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        log("开机自启：\(LoginItem.isEnabled ? "已开启" : "已关闭")")
        rebuildMenu()
    }

    @objc private func openConfigPage() {
        guard let ip = NetworkInfo.primaryLANAddress() else {
            log("无法打开配置页：未检测到局域网地址")
            return
        }
        let urlStr = "http://\(ip):\(defaultPort)/config.html?token=\(Pairing.token)"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showLog() {
        let alert = NSAlert()
        alert.messageText = "VibeCast 诊断日志"
        alert.informativeText = DiagnosticsLog.shared.snapshot(maxTail: 40).joined(separator: "\n")
        alert.addButton(withTitle: "导出诊断包…")
        alert.addButton(withTitle: "关闭")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            exportDiagnostics()
        }
    }

    private func exportDiagnostics() {
        guard let url = DiagnosticsLog.shared.export() else {
            log("诊断包导出失败")
            return
        }
        // 在 Finder 中选中导出的脱敏诊断包。
        NSWorkspace.shared.activateFileViewerSelecting([url])
        log("诊断包已导出: \(url.lastPathComponent)")
    }

    @objc private func quit() {
        server?.stop()
        NSApp.terminate(nil)
    }

    // MARK: - 日志（统一走脱敏 DiagnosticsLog）

    private func log(_ line: String) {
        DiagnosticsLog.shared.log(line)
    }

    // MARK: - SessionManagerDelegate

    func sessionPairedCountChanged(_ count: Int) {
        DispatchQueue.main.async {
            self.pairedCount = count
            self.updateStatusButton()
            self.rebuildMenu()
        }
    }

    func sessionDidLog(_ line: String) {
        DispatchQueue.main.async { self.log(line) }
    }

    func sessionConfigChanged() {
        DispatchQueue.main.async { self.rebuildMenu() }
    }
}
