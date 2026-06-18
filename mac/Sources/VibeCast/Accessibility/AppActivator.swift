// 通过 Bundle ID 激活/启动目标应用。PRD 9.1。

import AppKit

enum ActivationResult {
    case activated(pid: pid_t)
    case notRunning
    case launchFailed(String)
    case timeout
}

enum AppActivator {

    /// 激活已运行的应用；按需启动；等待其成为前台。
    /// - 同步等待（最多 timeout），返回结果。调用方应在后台队列调用。
    static func activate(bundleId: String, launchIfNotRunning: Bool, timeoutMs: Int) -> ActivationResult {
        guard !bundleId.isEmpty else { return .launchFailed("未配置 Bundle ID") }

        if let app = runningApp(bundleId: bundleId) {
            app.activate(options: [])
            if waitUntilFrontmost(bundleId: bundleId, timeoutMs: timeoutMs) {
                return .activated(pid: app.processIdentifier)
            }
            return .timeout
        }

        guard launchIfNotRunning else { return .notRunning }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return .launchFailed("未找到应用 \(bundleId)")
        }

        let sem = DispatchSemaphore(value: 0)
        var launchError: String?
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error { launchError = error.localizedDescription }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .milliseconds(timeoutMs))
        if let launchError { return .launchFailed(launchError) }

        if waitUntilFrontmost(bundleId: bundleId, timeoutMs: timeoutMs),
           let app = runningApp(bundleId: bundleId) {
            return .activated(pid: app.processIdentifier)
        }
        return .timeout
    }

    static func runningApp(bundleId: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// 轮询等待目标成为最前台应用。
    private static func waitUntilFrontmost(bundleId: String, timeoutMs: Int) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId {
                return true
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleId
    }
}
