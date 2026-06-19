// 目标应用配置 Profile。PRD 8 / 20。
// M3：定义结构 + 默认值 + JSON 持久化。完整配置页面在 M7。
// 不写死未经确认的 Bundle ID（PRD 8）：默认空，由用户在安装向导/配置页填写。

import Foundation

enum ActivationMode: String, Codable {
    case bundleId = "bundle_id"
}

/// 文本写入策略。
enum WriteMode: String, Codable {
    case auto            // 先 AXValue 直写，失败按 allowSelectAllReplace 决定是否剪贴板全选替换
    case axValue = "axvalue"        // 仅 AXValue 直写
    case clipboardPaste = "clipboard_paste" // 仅"粘贴到当前光标"（不全选）——适用 Electron/contenteditable
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
    /// accessibilityButton 模式下，按钮标题包含的文本（如 "发送"）。
    var sendButtonTitleContains: String?
    var clearAfterSend: Bool
    var allowEmpty: Bool
    var keepForeground: Bool
    var maxTextLength: Int
    /// 是否允许剪贴板降级时执行 Cmd+A 全选替换。
    /// Notion 当前文本块模式必须为 false，避免误全选整页文档（PRD 14.2）。
    var allowSelectAllReplace: Bool
    /// 文本写入策略。Electron/contenteditable（如 Notion AI 对话框）用 clipboardPaste。
    var writeMode: WriteMode

    // 向后兼容：旧配置文件无 writeMode 时默认 .auto。
    enum CodingKeys: String, CodingKey {
        case displayName, bundleId, activationMode, launchIfNotRunning, focusMode, focusShortcut
        case focusWaitMs, sendMode, sendShortcut, sendButtonTitleContains, clearAfterSend
        case allowEmpty, keepForeground, maxTextLength, allowSelectAllReplace, writeMode
    }

    init(displayName: String, bundleId: String, activationMode: ActivationMode, launchIfNotRunning: Bool,
         focusMode: FocusMode, focusShortcut: KeyShortcut?, focusWaitMs: Int, sendMode: SendMode,
         sendShortcut: KeyShortcut?, sendButtonTitleContains: String?, clearAfterSend: Bool,
         allowEmpty: Bool, keepForeground: Bool, maxTextLength: Int, allowSelectAllReplace: Bool,
         writeMode: WriteMode) {
        self.displayName = displayName; self.bundleId = bundleId; self.activationMode = activationMode
        self.launchIfNotRunning = launchIfNotRunning; self.focusMode = focusMode; self.focusShortcut = focusShortcut
        self.focusWaitMs = focusWaitMs; self.sendMode = sendMode; self.sendShortcut = sendShortcut
        self.sendButtonTitleContains = sendButtonTitleContains; self.clearAfterSend = clearAfterSend
        self.allowEmpty = allowEmpty; self.keepForeground = keepForeground; self.maxTextLength = maxTextLength
        self.allowSelectAllReplace = allowSelectAllReplace; self.writeMode = writeMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        bundleId = try c.decode(String.self, forKey: .bundleId)
        activationMode = try c.decode(ActivationMode.self, forKey: .activationMode)
        launchIfNotRunning = try c.decode(Bool.self, forKey: .launchIfNotRunning)
        focusMode = try c.decode(FocusMode.self, forKey: .focusMode)
        focusShortcut = try c.decodeIfPresent(KeyShortcut.self, forKey: .focusShortcut)
        focusWaitMs = try c.decode(Int.self, forKey: .focusWaitMs)
        sendMode = try c.decode(SendMode.self, forKey: .sendMode)
        sendShortcut = try c.decodeIfPresent(KeyShortcut.self, forKey: .sendShortcut)
        sendButtonTitleContains = try c.decodeIfPresent(String.self, forKey: .sendButtonTitleContains)
        clearAfterSend = try c.decode(Bool.self, forKey: .clearAfterSend)
        allowEmpty = try c.decode(Bool.self, forKey: .allowEmpty)
        keepForeground = try c.decode(Bool.self, forKey: .keepForeground)
        maxTextLength = try c.decode(Int.self, forKey: .maxTextLength)
        allowSelectAllReplace = try c.decode(Bool.self, forKey: .allowSelectAllReplace)
        writeMode = try c.decodeIfPresent(WriteMode.self, forKey: .writeMode) ?? .auto
    }

    static func defaultFor(_ id: TargetId) -> TargetProfile {
        let name = id.rawValue.capitalized
        switch id {
        case .notion:
            // Notion 默认面向 AI 对话框：恢复上次焦点 + 粘贴到光标（不全选）+ 仅同步不发送。
            return TargetProfile(
                displayName: name, bundleId: "", activationMode: .bundleId,
                launchIfNotRunning: false, focusMode: .preserveLastFocus, focusShortcut: nil,
                focusWaitMs: 300, sendMode: .noneSyncOnly, sendShortcut: nil,
                sendButtonTitleContains: nil,
                clearAfterSend: false, allowEmpty: false, keepForeground: false, maxTextLength: 10000,
                allowSelectAllReplace: false, writeMode: .clipboardPaste)
        default:
            return TargetProfile(
                displayName: name, bundleId: "", activationMode: .bundleId,
                launchIfNotRunning: true, focusMode: .shortcut, focusShortcut: nil,
                focusWaitMs: 250, sendMode: .key, sendShortcut: .enter,
                sendButtonTitleContains: nil,
                clearAfterSend: true, allowEmpty: false, keepForeground: false, maxTextLength: 10000,
                allowSelectAllReplace: true, writeMode: .auto)
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
