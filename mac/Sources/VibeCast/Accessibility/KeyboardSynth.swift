// 键盘事件合成（CGEvent）。用于聚焦快捷键与发送动作。PRD 9.2 / 13。
// 注意：仅用于「按配置的快捷键」，绝不逐字符模拟输入文本（PRD 10.3）。

import CoreGraphics
import Carbon.HIToolbox

enum KeyboardSynth {

    /// 主键名 → 虚拟键码（仅覆盖常用键）。
    private static let keyCodes: [String: CGKeyCode] = [
        "enter": CGKeyCode(kVK_Return),
        "return": CGKeyCode(kVK_Return),
        "tab": CGKeyCode(kVK_Tab),
        "space": CGKeyCode(kVK_Space),
        "escape": CGKeyCode(kVK_Escape),
        "delete": CGKeyCode(kVK_Delete),        // 退格删除（删除选中内容）
        "forwarddelete": CGKeyCode(kVK_ForwardDelete),
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

    @discardableResult
    static func keyDown(_ shortcut: KeyShortcut) -> Bool {
        post(shortcut, keyDown: true)
    }

    @discardableResult
    static func keyUp(_ shortcut: KeyShortcut) -> Bool {
        post(shortcut, keyDown: false)
    }

    private static func post(_ shortcut: KeyShortcut, keyDown: Bool) -> Bool {
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
}
