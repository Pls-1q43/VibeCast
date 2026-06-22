// 菜单栏 App 主控。PRD 7.3。
// 组装 Server + SessionManager，渲染状态栏菜单：运行状态/地址/连接数/权限/重启/日志/退出。

import AppKit
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, SessionManagerDelegate {
    private var statusItem: NSStatusItem!
    private var phoneServer: Server?
    private var configServer: Server?
    private var session: SessionManager!
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    private var aboutWindowController: AboutWindowController?
    private let networkSettings = NetworkSettingsStore()

    private var pairedCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusItem()

        let serverName = Host.current().localizedName ?? "Mac"
        session = SessionManager(serverName: serverName, accessibilityGranted: accessibilityGranted(),
                                 networkSettings: networkSettings)
        session.delegate = self

        // 首次启动：若未授权辅助功能，弹出系统授权提示（PRD 7.2）。
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.promptIfNeeded()
        }

        startConfigServer()
        startPhoneServer()
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

    private func startConfigServer() {
        guard configServer == nil else { return }
        guard let staticServer = StaticFileServer() else {
            log(MacI18n.t("missingResources"))
            return
        }
        for port in UInt16(8786)...UInt16(8795) {
            let srv = Server(port: port, bindHost: "127.0.0.1", staticServer: staticServer, routeMode: .config)
            srv.delegate = session
            do {
                try srv.start()
                configServer = srv
                log(MacI18n.f("configServiceStarted", Int(port)))
                return
            } catch {
                continue
            }
        }
        log(MacI18n.t("configServiceStartFailed"))
    }

    private func startPhoneServer(retryOnFailure: Bool = false, attempt: Int = 0) {
        guard let staticServer = StaticFileServer() else {
            log(MacI18n.t("missingResources"))
            return
        }
        let settings = networkSettings.normalizedForCurrentInterfaces()
        let bindHost = settings.bindMode == .all ? nil : settings.bindAddress
        let srv = Server(port: settings.port, bindHost: bindHost, staticServer: staticServer, routeMode: .phone)
        srv.delegate = session
        do {
            try srv.start()
            phoneServer = srv
            log(MacI18n.f("serviceStarted", bindHost ?? "*", Int(settings.port)))
        } catch {
            log(MacI18n.f("serviceStartFailed", String(describing: error)))
            if retryOnFailure && attempt < 5 {
                let delay = 0.25 + Double(attempt) * 0.25
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.startPhoneServer(retryOnFailure: true, attempt: attempt + 1)
                }
            }
        }
        rebuildMenu()
    }

    private func restartPhoneServer() {
        log(MacI18n.t("restarting"))
        phoneServer?.stop()
        phoneServer = nil
        pairedCount = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.startPhoneServer(retryOnFailure: true)
        }
    }

    private func restartAllServers() {
        log(MacI18n.t("restarting"))
        phoneServer?.stop()
        configServer?.stop()
        phoneServer = nil
        configServer = nil
        pairedCount = 0
        startConfigServer()
        startPhoneServer()
    }

    // MARK: - 权限

    private func accessibilityGranted() -> Bool {
        AccessibilityPermission.isGranted
    }

    // MARK: - 菜单

    private func rebuildMenu() {
        updateStatusButton()

        let menu = NSMenu()

        let running = phoneServer != nil
        menu.addItem(makeInfo(running ? MacI18n.t("serviceRunning") : MacI18n.t("serviceStopped")))

        if let url = accessURL(path: "/"), let ip = displayAddress() {
            menu.addItem(makeInfo(MacI18n.t("phoneAddress")))
            let addr = makeInfo("  \(ip):\(networkSettings.normalizedForCurrentInterfaces().port)")
            addr.toolTip = url
            menu.addItem(addr)
            let copyItem = NSMenuItem(title: MacI18n.t("copyAddress"), action: #selector(copyAddress), keyEquivalent: "")
            copyItem.target = self
            copyItem.representedObject = url
            menu.addItem(copyItem)
        } else {
            menu.addItem(makeInfo(MacI18n.t("noLAN")))
        }

        menu.addItem(makeInfo(MacI18n.f("connectedPhones", pairedCount)))
        menu.addItem(makeInfo(accessibilityGranted() ? MacI18n.t("accessibilityAuthorized") : MacI18n.t("accessibilityUnauthorized")))

        menu.addItem(.separator())

        if !accessibilityGranted() {
            let permItem = NSMenuItem(title: MacI18n.t("openAccessibility"), action: #selector(openAccessibilitySettings), keyEquivalent: "")
            permItem.target = self
            menu.addItem(permItem)
        }

        let configItem = NSMenuItem(title: MacI18n.t("openConfig"), action: #selector(openConfigPage), keyEquivalent: ",")
        configItem.target = self
        menu.addItem(configItem)

        let restartItem = NSMenuItem(title: MacI18n.t("restart"), action: #selector(restart), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let logItem = NSMenuItem(title: MacI18n.t("showLog"), action: #selector(showLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        let regenItem = NSMenuItem(title: MacI18n.t("regenerateToken"), action: #selector(regenToken), keyEquivalent: "")
        regenItem.target = self
        menu.addItem(regenItem)

        let loginItem = NSMenuItem(title: MacI18n.t("launchAtLogin"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: MacI18n.t("about"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: MacI18n.t("quit"), action: #selector(quit), keyEquivalent: "q")
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
        button.toolTip = pairedCount > 0 ? MacI18n.f("tooltipConnected", pairedCount) : "VibeCast"
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
        log(MacI18n.t("copied"))
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.openSettings()
    }

    @objc private func restart() {
        restartAllServers()
    }

    @objc private func regenToken() {
        Pairing.regenerate()
        session.revokePairings()
        log(MacI18n.t("tokenRegenerated"))
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        log(MacI18n.f("loginState", LoginItem.isEnabled ? MacI18n.t("loginOn") : MacI18n.t("loginOff")))
        rebuildMenu()
    }

    @objc private func openConfigPage() {
        guard let urlStr = configURL() else {
            log(MacI18n.t("configNoLAN"))
            return
        }
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func showLog() {
        let alert = NSAlert()
        alert.messageText = MacI18n.t("diagnosticsTitle")
        alert.informativeText = DiagnosticsLog.shared.snapshot(maxTail: 40).joined(separator: "\n")
        alert.addButton(withTitle: MacI18n.t("exportDiagnostics"))
        alert.addButton(withTitle: MacI18n.t("close"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            exportDiagnostics()
        }
    }

    private func exportDiagnostics() {
        guard let url = DiagnosticsLog.shared.export() else {
            log(MacI18n.t("diagnosticsFailed"))
            return
        }
        // 在 Finder 中选中导出的脱敏诊断包。
        NSWorkspace.shared.activateFileViewerSelecting([url])
        log(MacI18n.f("diagnosticsExported", url.lastPathComponent))
    }

    @objc private func showAbout() {
        if aboutWindowController == nil {
            aboutWindowController = AboutWindowController(updaterController: updaterController)
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindowController?.showWindow(nil)
        aboutWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        phoneServer?.stop()
        configServer?.stop()
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

    func sessionNetworkSettingsChanged(_ settings: NetworkSettings) {
        DispatchQueue.main.async {
            self.restartPhoneServer()
        }
    }

    private func displayAddress() -> String? {
        let settings = networkSettings.normalizedForCurrentInterfaces()
        switch settings.bindMode {
        case .all:
            return NetworkInfo.primaryLANAddress()
        case .address:
            return settings.bindAddress
        }
    }

    private func accessURL(path: String) -> String? {
        guard let host = displayAddress() else { return nil }
        let settings = networkSettings.normalizedForCurrentInterfaces()
        return "http://\(host):\(settings.port)\(path)?token=\(Pairing.token)"
    }

    private func configURL() -> String? {
        guard let port = configServer?.port else { return nil }
        return "http://127.0.0.1:\(port)/config.html?token=\(Pairing.token)"
    }
}
