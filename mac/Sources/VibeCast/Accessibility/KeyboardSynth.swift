// 键盘事件合成（CGEvent）。用于聚焦快捷键与发送动作。PRD 9.2 / 13。
// 注意：仅用于「按配置的快捷键」，绝不逐字符模拟输入文本（PRD 10.3）。

import CoreGraphics
import Carbon.HIToolbox

enum KeyboardSynth {
    private enum DictationShortcutKind {
        case dictationKey
        case doubleControl
        case other
    }

    private struct SystemDictationShortcut {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
        var pressCount: Int
        var kind: DictationShortcutKind
    }

    private static let appleSymbolicHotKeysPath =
        ("~/Library/Preferences/com.apple.symbolichotkeys.plist" as NSString).expandingTildeInPath
    private static let appleDictationModifierHotKeyId = "164"
    private static let appleDictationKeyHotKeyId = "175"
    private static let specialDictationKeyCode = CGKeyCode(178)

    /// 主键名 → 虚拟键码（仅覆盖常用键）。
    private static let keyCodes: [String: CGKeyCode] = [
        "enter": CGKeyCode(kVK_Return),
        "return": CGKeyCode(kVK_Return),
        "tab": CGKeyCode(kVK_Tab),
        "space": CGKeyCode(kVK_Space),
        "escape": CGKeyCode(kVK_Escape),
        "delete": CGKeyCode(kVK_Delete),        // 退格删除（删除选中内容）
        "forwarddelete": CGKeyCode(kVK_ForwardDelete),
        "f5": CGKeyCode(kVK_F5),
        "dictation": CGKeyCode(kVK_F5),
        "dictation_key": CGKeyCode(kVK_F5),
        "left_command": CGKeyCode(kVK_Command),
        "leftcommand": CGKeyCode(kVK_Command),
        "left_cmd": CGKeyCode(kVK_Command),
        "leftcmd": CGKeyCode(kVK_Command),
        "command_left": CGKeyCode(kVK_Command),
        "cmd_left": CGKeyCode(kVK_Command),
        "right_command": CGKeyCode(kVK_RightCommand),
        "rightcommand": CGKeyCode(kVK_RightCommand),
        "right_cmd": CGKeyCode(kVK_RightCommand),
        "rightcmd": CGKeyCode(kVK_RightCommand),
        "command_right": CGKeyCode(kVK_RightCommand),
        "cmd_right": CGKeyCode(kVK_RightCommand),
        "left_option": CGKeyCode(kVK_Option),
        "leftoption": CGKeyCode(kVK_Option),
        "left_opt": CGKeyCode(kVK_Option),
        "leftopt": CGKeyCode(kVK_Option),
        "option_left": CGKeyCode(kVK_Option),
        "opt_left": CGKeyCode(kVK_Option),
        "right_option": CGKeyCode(kVK_RightOption),
        "rightoption": CGKeyCode(kVK_RightOption),
        "right_opt": CGKeyCode(kVK_RightOption),
        "rightopt": CGKeyCode(kVK_RightOption),
        "option_right": CGKeyCode(kVK_RightOption),
        "opt_right": CGKeyCode(kVK_RightOption),
        "left_control": CGKeyCode(kVK_Control),
        "leftcontrol": CGKeyCode(kVK_Control),
        "left_ctrl": CGKeyCode(kVK_Control),
        "leftctrl": CGKeyCode(kVK_Control),
        "control_left": CGKeyCode(kVK_Control),
        "ctrl_left": CGKeyCode(kVK_Control),
        "right_control": CGKeyCode(kVK_RightControl),
        "rightcontrol": CGKeyCode(kVK_RightControl),
        "right_ctrl": CGKeyCode(kVK_RightControl),
        "rightctrl": CGKeyCode(kVK_RightControl),
        "control_right": CGKeyCode(kVK_RightControl),
        "ctrl_right": CGKeyCode(kVK_RightControl),
        "control": CGKeyCode(kVK_Control),
        "ctrl": CGKeyCode(kVK_Control),
        "left_shift": CGKeyCode(kVK_Shift),
        "leftshift": CGKeyCode(kVK_Shift),
        "shift_left": CGKeyCode(kVK_Shift),
        "right_shift": CGKeyCode(kVK_RightShift),
        "rightshift": CGKeyCode(kVK_RightShift),
        "shift_right": CGKeyCode(kVK_RightShift),
        "fn": CGKeyCode(kVK_Function),
        "function": CGKeyCode(kVK_Function),
        "a": CGKeyCode(kVK_ANSI_A), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
        "n": CGKeyCode(kVK_ANSI_N), "j": CGKeyCode(kVK_ANSI_J), "i": CGKeyCode(kVK_ANSI_I),
        "v": CGKeyCode(kVK_ANSI_V), "z": CGKeyCode(kVK_ANSI_Z),
    ]

    private static func flags(for modifiers: [String]) -> CGEventFlags {
        var f = CGEventFlags()
        for m in modifiers {
            switch m.lowercased() {
            case "command", "cmd": f.insert(.maskCommand)
            case "option", "opt", "alt": f.insert(.maskAlternate)
            case "control", "ctrl": f.insert(.maskControl)
            case "shift": f.insert(.maskShift)
            case "fn", "function": f.insert(.maskSecondaryFn)
            default: break
            }
        }
        return f
    }

    private static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isFunctionKey(_ key: String) -> Bool {
        switch normalizedKey(key) {
        case "fn", "function":
            return true
        default:
            return false
        }
    }

    private static func implicitFlag(for key: String) -> CGEventFlags {
        switch normalizedKey(key) {
        case "left_command", "leftcommand", "left_cmd", "leftcmd", "command_left", "cmd_left",
             "right_command", "rightcommand", "right_cmd", "rightcmd", "command_right", "cmd_right":
            return .maskCommand
        case "left_option", "leftoption", "left_opt", "leftopt", "option_left", "opt_left",
             "right_option", "rightoption", "right_opt", "rightopt", "option_right", "opt_right":
            return .maskAlternate
        case "left_control", "leftcontrol", "left_ctrl", "leftctrl", "control_left", "ctrl_left",
             "right_control", "rightcontrol", "right_ctrl", "rightctrl", "control_right", "ctrl_right":
            return .maskControl
        case "left_shift", "leftshift", "shift_left", "right_shift", "rightshift", "shift_right":
            return .maskShift
        case "fn", "function":
            return .maskSecondaryFn
        default:
            return []
        }
    }

    /// 向系统投递一个快捷键（键按下+抬起）。返回是否成功映射键码。
    @discardableResult
    static func press(_ shortcut: KeyShortcut) -> Bool {
        if isDoubleControl(shortcut.key) {
            return pressDoubleControl()
        }
        if isFunctionKey(shortcut.key) {
            guard postFunction(shortcut, keyDown: true) else { return false }
            Thread.sleep(forTimeInterval: 0.035)
            return postFunction(shortcut, keyDown: false)
        }
        guard let code = keyCode(for: shortcut) else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        let flags = flags(for: shortcut.modifiers)

        guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else {
            return false
        }
        let implicit = implicitFlag(for: shortcut.key)
        down.flags = flags.union(implicit)
        up.flags = flags
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.035)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// 触发 macOS 系统听写。它不是普通 F5：系统偏好会把听写记录成
    /// com.apple.symbolichotkeys 的特殊项，且需要投递到 session event tap。
    @discardableResult
    static func pressMacOSDictation(_ shortcut: KeyShortcut) -> Bool {
        let preferredKind = dictationKind(for: shortcut.key)
        if let systemShortcut = loadSystemDictationShortcut(preferredKind: preferredKind) {
            return postSystemDictationShortcut(systemShortcut)
        }

        switch preferredKind {
        case .dictationKey:
            return postSessionKeyPress(keyCode: specialDictationKeyCode, flags: [])
        case .doubleControl:
            return pressDoubleControlForDictation()
        case .other:
            return press(shortcut)
        }
    }

    @discardableResult
    static func keyDown(_ shortcut: KeyShortcut) -> Bool {
        post(shortcut, keyDown: true)
    }

    @discardableResult
    static func keyUp(_ shortcut: KeyShortcut) -> Bool {
        post(shortcut, keyDown: false)
    }

    private static func post(_ shortcut: KeyShortcut, keyDown: Bool) -> Bool {
        if isDoubleControl(shortcut.key) {
            return keyDown ? pressDoubleControl() : true
        }
        if isFunctionKey(shortcut.key) {
            return postFunction(shortcut, keyDown: keyDown)
        }
        guard let code = keyCode(for: shortcut),
              let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                                  virtualKey: code,
                                  keyDown: keyDown) else {
            return false
        }
        let explicit = flags(for: shortcut.modifiers)
        event.flags = keyDown ? explicit.union(implicitFlag(for: shortcut.key)) : explicit
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func postFunction(_ shortcut: KeyShortcut, keyDown: Bool) -> Bool {
        guard let event = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                                  virtualKey: CGKeyCode(kVK_Function),
                                  keyDown: keyDown) else {
            return false
        }
        let explicit = flags(for: shortcut.modifiers)
        event.flags = keyDown ? explicit.union(.maskSecondaryFn) : explicit
        event.post(tap: .cghidEventTap)
        return true
    }

    private static func keyCode(for shortcut: KeyShortcut) -> CGKeyCode? {
        keyCodes[normalizedKey(shortcut.key)]
    }

    private static func isDoubleControl(_ key: String) -> Bool {
        switch normalizedKey(key) {
        case "control_double", "double_control", "ctrl_double", "double_ctrl":
            return true
        default:
            return false
        }
    }

    private static func pressDoubleControl() -> Bool {
        let control = KeyShortcut(modifiers: [], key: "control")
        guard press(control) else { return false }
        Thread.sleep(forTimeInterval: 0.08)
        return press(control)
    }

    private static func dictationKind(for key: String) -> DictationShortcutKind {
        switch normalizedKey(key) {
        case "f5", "dictation", "dictation_key":
            return .dictationKey
        case "control_double", "double_control", "ctrl_double", "double_ctrl":
            return .doubleControl
        default:
            return .other
        }
    }

    private static func loadSystemDictationShortcut(preferredKind: DictationShortcutKind) -> SystemDictationShortcut? {
        guard let root = NSDictionary(contentsOfFile: appleSymbolicHotKeysPath) as? [String: Any],
              let hotKeys = root["AppleSymbolicHotKeys"] as? [String: Any] else {
            return nil
        }

        let candidates: [String]
        switch preferredKind {
        case .dictationKey:
            candidates = [appleDictationKeyHotKeyId, appleDictationModifierHotKeyId]
        case .doubleControl:
            candidates = [appleDictationModifierHotKeyId, appleDictationKeyHotKeyId]
        case .other:
            candidates = [appleDictationKeyHotKeyId, appleDictationModifierHotKeyId]
        }

        for id in candidates {
            guard let shortcut = parseSystemDictationShortcut(hotKeys[id]) else { continue }
            if preferredKind == .other || shortcut.kind == preferredKind {
                return shortcut
            }
        }
        return nil
    }

    private static func parseSystemDictationShortcut(_ raw: Any?) -> SystemDictationShortcut? {
        guard let dictation = raw as? [String: Any],
              (dictation["enabled"] as? NSNumber)?.boolValue == true,
              let value = dictation["value"] as? [String: Any],
              let type = value["type"] as? String,
              let parameters = value["parameters"] as? [NSNumber] else {
            return nil
        }
        if type == "standard", parameters.count >= 3 {
            let keyCode = CGKeyCode(parameters[1].uint16Value)
            let flags = CGEventFlags(rawValue: parameters[2].uint64Value)
            return SystemDictationShortcut(keyCode: keyCode,
                                           flags: flags,
                                           pressCount: 1,
                                           kind: keyCode == specialDictationKeyCode || keyCode == CGKeyCode(kVK_F5) ? .dictationKey : .other)
        }

        guard let keyCode = modifierKeyCode(from: parameters.first?.uint64Value ?? 0) else {
            return nil
        }
        let kind: DictationShortcutKind = keyCode == CGKeyCode(kVK_Control) || keyCode == CGKeyCode(kVK_RightControl) ? .doubleControl : .other
        return SystemDictationShortcut(keyCode: keyCode,
                                       flags: [],
                                       pressCount: 2,
                                       kind: kind)
    }

    private static func modifierKeyCode(from mask: UInt64) -> CGKeyCode? {
        if (mask & 0x0010_0008) == 0x0010_0008 { return CGKeyCode(kVK_Command) }
        if (mask & 0x0010_0010) == 0x0010_0010 { return CGKeyCode(kVK_RightCommand) }
        if (mask & CGEventFlags.maskCommand.rawValue) == CGEventFlags.maskCommand.rawValue { return CGKeyCode(kVK_Command) }
        if (mask & CGEventFlags.maskSecondaryFn.rawValue) == CGEventFlags.maskSecondaryFn.rawValue { return CGKeyCode(kVK_Function) }
        if (mask & CGEventFlags.maskControl.rawValue) == CGEventFlags.maskControl.rawValue { return CGKeyCode(kVK_Control) }
        if (mask & CGEventFlags.maskAlternate.rawValue) == CGEventFlags.maskAlternate.rawValue { return CGKeyCode(kVK_Option) }
        if (mask & CGEventFlags.maskShift.rawValue) == CGEventFlags.maskShift.rawValue { return CGKeyCode(kVK_Shift) }
        return nil
    }

    private static func postSystemDictationShortcut(_ shortcut: SystemDictationShortcut) -> Bool {
        var ok = true
        for index in 0..<max(1, shortcut.pressCount) {
            ok = postSessionKeyPress(keyCode: shortcut.keyCode, flags: shortcut.flags) && ok
            if index + 1 < shortcut.pressCount {
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
        return ok
    }

    private static func pressDoubleControlForDictation() -> Bool {
        let first = postSessionKeyPress(keyCode: CGKeyCode(kVK_Control), flags: [])
        Thread.sleep(forTimeInterval: 0.12)
        let second = postSessionKeyPress(keyCode: CGKeyCode(kVK_Control), flags: [])
        return first && second
    }

    private static func postSessionKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.04)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
