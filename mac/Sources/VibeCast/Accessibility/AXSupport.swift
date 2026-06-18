// macOS Accessibility (AX) 辅助查询。PRD 9.2 / 9.3 / 10.1。

import ApplicationServices
import AppKit

enum AXSupport {

    /// 取某进程当前聚焦的 UI 元素。
    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        // CFTypeRef → AXUIElement
        return (v as! AXUIElement)
    }

    /// 取系统范围当前聚焦元素（用于校验前台焦点）。
    static func systemFocusedElement() -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &value)
        guard err == .success, let v = value else { return nil }
        return (v as! AXUIElement)
    }

    static func role(of element: AXUIElement) -> String? {
        stringAttr(element, kAXRoleAttribute)
    }

    static func stringAttr(_ element: AXUIElement, _ attr: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// 元素是否为可编辑文本控件。
    static func isEditableText(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return false }
        if role == kAXTextAreaRole as String || role == kAXTextFieldRole as String {
            return true
        }
        // 某些 web/Electron 控件 role 不标准，回退检查是否支持 AXValue 设置。
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success {
            return settable.boolValue
        }
        return false
    }

    /// 取元素所属进程 PID。
    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }

    /// 读取元素文本值。
    static func value(of element: AXUIElement) -> String? {
        stringAttr(element, kAXValueAttribute)
    }
}
