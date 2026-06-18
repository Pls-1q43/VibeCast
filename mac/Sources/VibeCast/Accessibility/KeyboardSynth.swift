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
        "a": CGKeyCode(kVK_ANSI_A), "k": CGKeyCode(kVK_ANSI_K), "l": CGKeyCode(kVK_ANSI_L),
        "n": CGKeyCode(kVK_ANSI_N), "j": CGKeyCode(kVK_ANSI_J), "i": CGKeyCode(kVK_ANSI_I),
        "v": CGKeyCode(kVK_ANSI_V),
    ]

    private static func flags(for modifiers: [String]) -> CGEventFlags {
        var f = CGEventFlags()
        for m in modifiers {
            switch m.lowercased() {
            case "command", "cmd": f.insert(.maskCommand)
            case "option", "opt", "alt": f.insert(.maskAlternate)
            case "control", "ctrl": f.insert(.maskControl)
            case "shift": f.insert(.maskShift)
            default: break
            }
        }
        return f
    }

    /// 向系统投递一个快捷键（键按下+抬起）。返回是否成功映射键码。
    @discardableResult
    static func press(_ shortcut: KeyShortcut) -> Bool {
        guard let code = keyCodes[shortcut.key.lowercased()] else { return false }
        let src = CGEventSource(stateID: .hidSystemState)
        let flags = flags(for: shortcut.modifiers)

        guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
