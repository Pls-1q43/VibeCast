import AppKit
import Foundation

enum DoubaoImeBridge {
    private static let bundleIdentifier = "com.bytedance.inputmethod.doubaoime"
    private static let appPath = "/Library/Input Methods/DoubaoIme.app"

    @discardableResult
    static func reloadForInputDeviceChange(launchIfNotRunning: Bool = true) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !running.isEmpty else {
            return launchIfNotRunning ? launchApp() : true
        }

        for app in running {
            app.terminate()
        }

        waitUntilTerminated(running, timeout: 1.0)

        for app in running where !app.isTerminated {
            app.forceTerminate()
        }

        waitUntilTerminated(running, timeout: 1.0)
        return launchApp()
    }

    private static func waitUntilTerminated(_ apps: [NSRunningApplication], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && apps.contains(where: { !$0.isTerminated }) {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private static func launchApp() -> Bool {
        if runOpen(arguments: ["-g", "-j", "-b", bundleIdentifier]), waitUntilRunning(timeout: 2.0) {
            return true
        }
        if FileManager.default.fileExists(atPath: appPath),
           runOpen(arguments: ["-g", "-j", appPath]),
           waitUntilRunning(timeout: 2.0) {
            return true
        }
        return false
    }

    private static func runOpen(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func waitUntilRunning(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                Thread.sleep(forTimeInterval: 0.2)
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}
