// 列出当前运行的常规应用，供配置页选择 Bundle ID（PRD 8 安装向导）。

import AppKit

enum RunningAppsProvider {
    /// 返回有界面的常规应用（排除后台/无 Bundle ID），按名称排序去重。
    static func visibleApps() -> [RunningApp] {
        var seen = Set<String>()
        var result: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleId = app.bundleIdentifier,
                  let name = app.localizedName,
                  !seen.contains(bundleId) else { continue }
            seen.insert(bundleId)
            result.append(RunningApp(bundleId: bundleId, name: name,
                                     iconDataUrl: TargetIconProvider.iconDataURL(app: app)))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
