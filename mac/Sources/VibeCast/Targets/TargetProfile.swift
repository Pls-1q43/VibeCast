// 目标应用配置 Profile。PRD 8 / 20。
// M3：定义结构 + 默认值 + JSON 持久化。完整配置页面在 M7。
// 不写死未经确认的 Bundle ID（PRD 8）：默认空，由用户在安装向导/配置页填写。

import Foundation

enum ActivationMode: String, Codable {
    case bundleId = "bundle_id"
}

enum FocusMode: String, Codable {
    case shortcut          // 策略一：应用快捷键
    case accessibility     // 策略二：AX 查找输入控件（M3-2 实现）
    case preserveLastFocus = "preserve_last_focus" // 策略三：恢复上次焦点
    case custom            // 策略四：自定义动作（二期）
}

enum SendMode: String, Codable {
    case key
    case customShortcut = "custom_shortcut"
    case accessibilityButton = "accessibility_button"
    case noneSyncOnly = "none"
}

/// 键盘快捷键描述（修饰键 + 主键）。
struct KeyShortcut: Codable, Equatable {
    var modifiers: [String]  // "command" | "option" | "control" | "shift"
    var key: String          // "enter" | "a" | "k" ...

    static let enter = KeyShortcut(modifiers: [], key: "enter")
}

struct TargetProfile: Codable {
    var displayName: String
    var bundleId: String
    var activationMode: ActivationMode
    var launchIfNotRunning: Bool
    var focusMode: FocusMode
    var focusShortcut: KeyShortcut?
    var focusWaitMs: Int
    var sendMode: SendMode
    var sendShortcut: KeyShortcut?
    var clearAfterSend: Bool
    var allowEmpty: Bool
    var keepForeground: Bool
    var maxTextLength: Int

    static func defaultFor(_ id: TargetId) -> TargetProfile {
        let name = id.rawValue.capitalized
        switch id {
        case .notion:
            // Notion 默认当前文本块模式：仅同步、不自动发送（PRD 14.2）。
            return TargetProfile(
                displayName: name, bundleId: "", activationMode: .bundleId,
                launchIfNotRunning: false, focusMode: .preserveLastFocus, focusShortcut: nil,
                focusWaitMs: 300, sendMode: .noneSyncOnly, sendShortcut: nil,
                clearAfterSend: false, allowEmpty: false, keepForeground: false, maxTextLength: 10000)
        default:
            return TargetProfile(
                displayName: name, bundleId: "", activationMode: .bundleId,
                launchIfNotRunning: true, focusMode: .shortcut, focusShortcut: nil,
                focusWaitMs: 250, sendMode: .key, sendShortcut: .enter,
                clearAfterSend: true, allowEmpty: false, keepForeground: false, maxTextLength: 10000)
        }
    }
}

/// 全部目标的配置集合，JSON 持久化到 Application Support。
final class TargetConfigStore {
    private(set) var profiles: [TargetId: TargetProfile]
    private let fileURL: URL

    init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("VibeCast", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("targets.json")
        self.profiles = TargetConfigStore.load(from: fileURL)
    }

    private static func load(from url: URL) -> [TargetId: TargetProfile] {
        var result: [TargetId: TargetProfile] = [:]
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: TargetProfile].self, from: data) {
            for (k, v) in decoded {
                if let id = TargetId(rawValue: k) { result[id] = v }
            }
        }
        // 补齐缺失目标为默认值。
        for id in TargetId.allCases where result[id] == nil {
            result[id] = .defaultFor(id)
        }
        return result
    }

    func profile(_ id: TargetId) -> TargetProfile {
        profiles[id] ?? .defaultFor(id)
    }

    func update(_ id: TargetId, _ profile: TargetProfile) {
        profiles[id] = profile
        persist()
    }

    private func persist() {
        var dict: [String: TargetProfile] = [:]
        for (k, v) in profiles { dict[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: fileURL)
        }
    }
}
