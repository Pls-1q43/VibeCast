// 目标应用配置 Profile。PRD 8 / 20。
// M3：定义结构 + 默认值 + JSON 持久化。完整配置页面在 M7。
import AppKit
import Foundation

enum ActivationMode: String, Codable {
    case bundleId = "bundle_id"
}

/// 文本写入策略。
enum WriteMode: String, Codable {
    case auto            // 先 AXValue 直写，失败按 allowSelectAllReplace 决定是否剪贴板全选替换
    case axValue = "axvalue"        // 仅 AXValue 直写
    case clipboardReplace = "clipboard_replace" // 剪贴板全选替换；必须 allowSelectAllReplace=true
    case clipboardInsert = "clipboard_insert" // 剪贴板插入到当前光标；不保证镜像替换
    case clipboardPaste = "clipboard_paste" // 旧配置名；发布版按 clipboardReplace 处理，但受 allowSelectAllReplace 保护
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

extension WriteMode {
    var usesClipboard: Bool {
        self == .clipboardReplace || self == .clipboardInsert || self == .clipboardPaste
    }
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
    var iconDataUrl: String?
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
        case displayName, bundleId, iconDataUrl, activationMode, launchIfNotRunning, focusMode, focusShortcut
        case focusWaitMs, sendMode, sendShortcut, sendButtonTitleContains, clearAfterSend
        case allowEmpty, keepForeground, maxTextLength, allowSelectAllReplace, writeMode
    }

    init(displayName: String, bundleId: String, activationMode: ActivationMode, launchIfNotRunning: Bool,
         focusMode: FocusMode, focusShortcut: KeyShortcut?, focusWaitMs: Int, sendMode: SendMode,
         sendShortcut: KeyShortcut?, sendButtonTitleContains: String?, clearAfterSend: Bool,
         allowEmpty: Bool, keepForeground: Bool, maxTextLength: Int, allowSelectAllReplace: Bool,
         writeMode: WriteMode, iconDataUrl: String? = nil) {
        self.displayName = displayName; self.bundleId = bundleId; self.iconDataUrl = iconDataUrl; self.activationMode = activationMode
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
        iconDataUrl = try c.decodeIfPresent(String.self, forKey: .iconDataUrl)
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
        let preset = PresetTargetCatalog.definition(for: id)
        let name = preset?.displayName ?? id.rawValue.capitalized
        let bundleId = preset?.bundleId ?? ""
        if id == .notion {
            // Notion AI 输入框通常是 Electron/contenteditable，AXValue 可能只改到
            // accessibility 层的“虚值”。默认走剪贴板替换，并要求用户先把焦点放进 AI 输入框。
            return TargetProfile(
                displayName: name, bundleId: bundleId, activationMode: .bundleId,
                launchIfNotRunning: false, focusMode: .preserveLastFocus, focusShortcut: nil,
                focusWaitMs: 300, sendMode: .key, sendShortcut: .enter,
                sendButtonTitleContains: nil,
                clearAfterSend: true, allowEmpty: false, keepForeground: false, maxTextLength: 10000,
                allowSelectAllReplace: true, writeMode: .clipboardReplace)
        }
        return TargetProfile(
            displayName: name, bundleId: bundleId, activationMode: .bundleId,
            launchIfNotRunning: true, focusMode: .shortcut, focusShortcut: nil,
            focusWaitMs: 250, sendMode: .key, sendShortcut: .enter,
            sendButtonTitleContains: nil,
            clearAfterSend: true, allowEmpty: false, keepForeground: false, maxTextLength: 10000,
            allowSelectAllReplace: true, writeMode: .auto)
    }
}

struct PresetTargetDefinition {
    let id: TargetId
    let displayName: String
    let bundleId: String
}

enum PresetTargetCatalog {
    static let definitions: [PresetTargetDefinition] = [
        PresetTargetDefinition(id: .codex, displayName: "Codex", bundleId: "com.openai.codex"),
        PresetTargetDefinition(id: .workbuddy, displayName: "WorkBuddy", bundleId: "com.workbuddy.workbuddy"),
        PresetTargetDefinition(id: .notion, displayName: "Notion", bundleId: "notion.id"),
        PresetTargetDefinition(id: .codebuddycn, displayName: "CodeBuddyCN", bundleId: "com.tencent.codebuddycn"),
        PresetTargetDefinition(id: .codebuddy, displayName: "CodeBuddy", bundleId: "com.tencent.codebuddy")
    ]

    static func definition(for id: TargetId) -> PresetTargetDefinition? {
        definitions.first { $0.id == id }
    }

    static func isInstalled(bundleId: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
    }
}

struct TargetConfigEntry: Codable, Sendable {
    var id: TargetId
    var kind: TargetKind
    var enabled: Bool
    var profile: TargetProfile

    func normalized() -> TargetConfigEntry {
        var entry = self
        entry.profile = entry.profile.normalized()
        return entry
    }
}

/// 全部目标的配置集合，JSON 持久化到 Application Support。
final class TargetConfigStore {
    private(set) var entries: [TargetId: TargetConfigEntry]
    private let fileURL: URL

    init(fileURL: URL? = nil, isBundleInstalled: ((String) -> Bool)? = nil) {
        let fm = FileManager.default
        if let fileURL {
            self.fileURL = fileURL
            try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } else {
            let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("VibeCast", isDirectory: true)
            try? fm.createDirectory(at: base, withIntermediateDirectories: true)
            self.fileURL = base.appendingPathComponent("targets.json")
        }
        self.entries = TargetConfigStore.load(from: self.fileURL,
                                              isBundleInstalled: isBundleInstalled ?? PresetTargetCatalog.isInstalled)
    }

    private struct StoredConfig: Codable {
        var targets: [TargetConfigEntry]
    }

    private static func load(from url: URL, isBundleInstalled: (String) -> Bool) -> [TargetId: TargetConfigEntry] {
        var result = presetEntries(isBundleInstalled: isBundleInstalled)
        guard let data = try? Data(contentsOf: url) else { return result }

        if let decoded = try? JSONDecoder().decode(StoredConfig.self, from: data) {
            for entry in decoded.targets {
                result[entry.id] = migrateStoredEntry(entry, isBundleInstalled: isBundleInstalled)
            }
            return fillMissingPresets(result, isBundleInstalled: isBundleInstalled)
        }

        // 兼容旧版 targets.json: { "codex": TargetProfile, ... }
        if let decoded = try? JSONDecoder().decode([String: TargetProfile].self, from: data) {
            for (k, v) in decoded {
                if let id = TargetId(rawValue: k) {
                    let kind: TargetKind = TargetId.presetIds.contains(id) ? .preset : .custom
                    let entry = TargetConfigEntry(id: id, kind: kind, enabled: true, profile: v)
                    result[id] = migrateStoredEntry(entry, isBundleInstalled: isBundleInstalled)
                }
            }
            return fillMissingPresets(result, isBundleInstalled: isBundleInstalled)
        }

        return result
    }

    private static func presetEntries(isBundleInstalled: (String) -> Bool) -> [TargetId: TargetConfigEntry] {
        var result: [TargetId: TargetConfigEntry] = [:]
        for id in TargetId.presetIds {
            result[id] = presetEntry(for: id, isBundleInstalled: isBundleInstalled)
        }
        return result
    }

    private static func fillMissingPresets(_ entries: [TargetId: TargetConfigEntry],
                                           isBundleInstalled: (String) -> Bool) -> [TargetId: TargetConfigEntry] {
        var result = entries
        for id in TargetId.presetIds where result[id] == nil {
            result[id] = presetEntry(for: id, isBundleInstalled: isBundleInstalled)
        }
        return result
    }

    private static func presetEntry(for id: TargetId, isBundleInstalled: (String) -> Bool) -> TargetConfigEntry {
        let profile = TargetProfile.defaultFor(id).normalized()
        let enabled = !profile.bundleId.isEmpty && isBundleInstalled(profile.bundleId)
        return TargetConfigEntry(id: id, kind: .preset, enabled: enabled, profile: profile)
    }

    private static func migrateStoredEntry(_ entry: TargetConfigEntry,
                                           isBundleInstalled: (String) -> Bool) -> TargetConfigEntry {
        var migrated = entry.normalized()
        guard let definition = PresetTargetCatalog.definition(for: migrated.id) else { return migrated }

        migrated.kind = .preset
        let previousBundleId = migrated.profile.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        if previousBundleId.isEmpty {
            migrated.profile.bundleId = definition.bundleId
            if migrated.enabled {
                migrated.enabled = isBundleInstalled(definition.bundleId)
            }
        }
        if migrated.profile.displayName == migrated.id.rawValue.capitalized {
            migrated.profile.displayName = definition.displayName
        }
        migrated.profile = migrated.profile.normalized()
        return migrated
    }

    var allTargets: [TargetConfigEntry] {
        let presetOrder = Dictionary(uniqueKeysWithValues: TargetId.presetIds.enumerated().map { ($0.element, $0.offset) })
        return entries.values.sorted { a, b in
            switch (a.kind, b.kind) {
            case (.preset, .preset):
                return (presetOrder[a.id] ?? 0) < (presetOrder[b.id] ?? 0)
            case (.preset, .custom):
                return true
            case (.custom, .preset):
                return false
            case (.custom, .custom):
                return a.profile.displayName.localizedCaseInsensitiveCompare(b.profile.displayName) == .orderedAscending
            }
        }
    }

    var activeTargets: [TargetConfigEntry] {
        allTargets.filter { $0.enabled && !$0.profile.bundleId.isEmpty }
    }

    func entry(_ id: TargetId) -> TargetConfigEntry? {
        entries[id]
    }

    func profile(_ id: TargetId) -> TargetProfile {
        entries[id]?.profile ?? .defaultFor(id)
    }

    func isUsable(_ id: TargetId) -> Bool {
        guard let entry = entries[id] else { return false }
        return entry.enabled && !entry.profile.bundleId.isEmpty
    }

    @discardableResult
    func update(_ id: TargetId, _ profile: TargetProfile) -> Bool {
        guard var entry = entries[id] else { return false }
        entry.profile = profile
        entries[id] = entry.normalized()
        persist()
        return true
    }

    @discardableResult
    func setEnabled(_ id: TargetId, enabled: Bool) -> Bool {
        guard var entry = entries[id] else { return false }
        entry.enabled = enabled
        entries[id] = entry
        persist()
        return true
    }

    @discardableResult
    func createCustom(displayName: String, bundleId: String?, iconDataUrl: String? = nil) -> TargetConfigEntry {
        let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanName.isEmpty ? "Custom App" : cleanName
        let id = uniqueCustomId(base: bundleId?.isEmpty == false ? bundleId! : name)
        var profile = TargetProfile.defaultFor(id)
        profile.displayName = name
        profile.bundleId = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        profile.iconDataUrl = TargetProfile.normalizedIconDataURL(iconDataUrl)
            ?? TargetIconProvider.iconDataURL(bundleId: profile.bundleId)
        let entry = TargetConfigEntry(id: id, kind: .custom, enabled: true, profile: profile.normalized())
        entries[id] = entry
        persist()
        return entry
    }

    @discardableResult
    func deleteCustom(_ id: TargetId) -> Bool {
        guard entries[id]?.kind == .custom else { return false }
        entries.removeValue(forKey: id)
        persist()
        return true
    }

    private func persist() {
        let stored = StoredConfig(targets: allTargets)
        if let data = try? JSONEncoder().encode(stored) {
            try? data.write(to: fileURL)
        }
    }

    private func uniqueCustomId(base: String) -> TargetId {
        let slugSource = base.lowercased()
        var slug = ""
        for ch in slugSource {
            if ch.isLetter || ch.isNumber {
                slug.append(ch)
            } else if ch == "." || ch == "-" || ch == "_" || ch.isWhitespace {
                if !slug.hasSuffix("_") { slug.append("_") }
            }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "_-."))
        if slug.isEmpty { slug = "app" }
        if slug.count > 40 { slug = String(slug.prefix(40)) }

        var candidate = TargetId(rawValue: "custom_\(slug)")!
        var i = 2
        while entries[candidate] != nil {
            candidate = TargetId(rawValue: "custom_\(slug)_\(i)")!
            i += 1
        }
        return candidate
    }
}

extension TargetProfile {
    func normalized() -> TargetProfile {
        var p = self
        p.displayName = p.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.displayName.isEmpty { p.displayName = "Target" }
        p.bundleId = p.bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        p.iconDataUrl = TargetProfile.normalizedIconDataURL(p.iconDataUrl)
        p.focusWaitMs = min(max(p.focusWaitMs, 50), 5_000)
        p.maxTextLength = min(max(p.maxTextLength, 1), 50_000)
        if (p.sendMode == .key || p.sendMode == .customShortcut), p.sendShortcut == nil {
            p.sendShortcut = .enter
        }
        if p.writeMode == .clipboardPaste {
            p.writeMode = .clipboardReplace
        }
        if p.writeMode == .clipboardInsert {
            p.allowSelectAllReplace = false
        }
        return p
    }

    static func normalizedIconDataURL(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= 200_000 else { return nil }
        let allowedPrefixes = [
            "data:image/png;base64,",
            "data:image/jpeg;base64,",
            "data:image/jpg;base64,",
            "data:image/webp;base64,",
            "data:image/svg+xml;base64,"
        ]
        guard allowedPrefixes.contains(where: { trimmed.lowercased().hasPrefix($0) }) else { return nil }
        return trimmed
    }
}
