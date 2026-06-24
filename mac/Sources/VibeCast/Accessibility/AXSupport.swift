// macOS Accessibility (AX) 辅助查询。PRD 9.2 / 9.3 / 10.1。

import ApplicationServices
import AppKit

enum AXSupport {

    /// 取某进程当前聚焦的 UI 元素。
    /// Electron 应用（如 Notion/VS Code）默认不暴露完整 AX 树，需先打开 AXManualAccessibility；
    /// 且其 AXFocusedUIElement 常为空，此时从聚焦窗口向下查找可编辑元素兜底。
    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)

        // Electron/Chromium：开启手动 accessibility（幂等，原生应用忽略）。
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        // 1) 直接取应用级聚焦元素。
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let v = value {
            return (v as! AXUIElement)
        }

        // 2) 兜底：从聚焦窗口子树里找第一个可编辑文本控件。
        var winRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
           let win = winRef {
            return findEditable(in: (win as! AXUIElement), depth: 18)
        }
        return nil
    }

    /// 在子树中深度优先查找首个可编辑文本元素（用于 Electron 焦点兜底）。
    private static func findEditable(in element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth < 0 { return nil }
        // 优先返回当前聚焦元素（若该子节点声明了焦点）。
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
           let f = focusedRef {
            let fe = f as! AXUIElement
            if isEditableText(fe) { return fe }
        }
        if isEditableText(element) { return element }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findEditable(in: child, depth: depth - 1) { return found }
        }
        return nil
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

    /// AXValue 是否可直接设置。
    static func isValueSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    /// 直接设置元素文本值（AXValue 直写）。返回是否成功。
    @discardableResult
    static func setValue(_ element: AXUIElement, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef) == .success
    }

    /// 设置选区（写入后把光标放到末尾，避免后续操作位置异常）。
    static func setSelectionToEnd(_ element: AXUIElement, length: Int) {
        let range = CFRangeMake(length, 0)
        if let axValue = AXValueCreate(.cfRange, withUnsafePointer(to: range, { $0 })) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue)
        }
    }

    /// 读取当前文本选区。复杂编辑器若不暴露该属性，调用方必须安全失败。
    static func selectedTextRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let axValue = value else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue((axValue as! AXValue), .cfRange, &range) else { return nil }
        return range
    }

    /// 设置当前文本选区。用于 editor 模式只替换本轮插入段，禁止退回整页全选。
    @discardableResult
    static func setSelectedTextRange(_ element: AXUIElement, range: CFRange) -> Bool {
        guard let axValue = AXValueCreate(.cfRange, withUnsafePointer(to: range, { $0 })) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    /// 在某进程窗口树中查找标题包含给定文本的按钮并按下（AXPress）。
    /// 仅遍历有限深度，避免在复杂界面上无限递归。返回是否成功按下。
    static func pressButton(pid: pid_t, titleContains: String, maxDepth: Int = 12) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let button = findButton(in: app, titleContains: titleContains, depth: maxDepth) else {
            return false
        }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    private static func findButton(in element: AXUIElement, titleContains: String, depth: Int) -> AXUIElement? {
        if depth < 0 { return nil }
        if role(of: element) == (kAXButtonRole as String) {
            let title = stringAttr(element, kAXTitleAttribute) ?? stringAttr(element, kAXDescriptionAttribute) ?? ""
            if title.contains(titleContains) { return element }
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let found = findButton(in: child, titleContains: titleContains, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
}
