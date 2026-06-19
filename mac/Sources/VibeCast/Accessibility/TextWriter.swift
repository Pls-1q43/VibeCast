// 目标输入框文本写入。PRD 10。
// 首选 AXValue 直写；不支持时降级为剪贴板全量替换（含剪贴板备份/恢复）。
// 安全红线（PRD 10.3）：
//   - 绝不逐字符模拟键盘
//   - 绝不在未校验目标焦点时执行全选/粘贴
//   - 绝不永久覆盖用户剪贴板

import AppKit
import ApplicationServices

enum WriteResult {
    case applied(method: String)
    case failed(String)
}

enum TextWriter {

    /// 把完整文本写入已校验有效的绑定目标。调用方必须先 FocusController.validate 通过。
    /// - allowSelectAllReplace: 剪贴板降级时是否允许 Cmd+A 全选替换。
    ///   Notion 文本块模式必须为 false，避免误全选整页（PRD 14.2）。
    static func write(_ text: String, to binding: TargetBinding, allowSelectAllReplace: Bool = true) -> WriteResult {
        // 长度护栏由上层 Profile 控制；此处再次防御空指针等。
        if AXSupport.isValueSettable(binding.element) {
            if AXSupport.setValue(binding.element, text) {
                // 验证写入结果（部分控件 set 成功但值未变）。
                if verify(binding.element, expects: text) {
                    AXSupport.setSelectionToEnd(binding.element, length: text.count)
                    return .applied(method: "axvalue")
                }
                // 直写未生效，落入剪贴板降级。
            }
        }
        // AXValue 直写失败且不允许全选替换：拒绝，绝不冒险全选整页（PRD 14.2）。
        guard allowSelectAllReplace else {
            return .failed("AXValue 直写失败且该目标禁止全选替换（保护整页文档）")
        }
        return writeViaClipboard(text, to: binding)
    }

    private static func verify(_ element: AXUIElement, expects text: String) -> Bool {
        // 读取回填值比对；某些控件归一化空白，故只要求前缀/全等其一。
        guard let current = AXSupport.value(of: element) else { return false }
        return current == text
    }

    // MARK: - 剪贴板降级（PRD 10.2）

    private static func writeViaClipboard(_ text: String, to binding: TargetBinding) -> WriteResult {
        // 再次确认目标仍在前台（粘贴前最后一道防线）。
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == binding.pid else {
            return .failed("粘贴前目标已失焦")
        }

        let pasteboard = NSPasteboard.general
        // 1) 备份当前剪贴板（保留所有类型尽力而为；至少保留字符串）。
        let savedItems = backupPasteboard(pasteboard)

        defer {
            // 5) 恢复用户剪贴板（无论成功与否）。
            restorePasteboard(pasteboard, items: savedItems)
        }

        // 2) 放入目标文本
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3) 全选（仅在已校验焦点的前提下）→ 4) 粘贴
        guard KeyboardSynth.press(KeyShortcut(modifiers: ["command"], key: "a")) else {
            return .failed("无法发送全选")
        }
        Thread.sleep(forTimeInterval: 0.03)
        guard KeyboardSynth.press(KeyShortcut(modifiers: ["command"], key: "v")) else {
            return .failed("无法发送粘贴")
        }
        // 给目标应用时间处理粘贴并回填 AXValue。
        Thread.sleep(forTimeInterval: 0.08)

        // 6) 验证：尽力读取 AXValue 比对（部分控件粘贴后可读）。
        if verify(binding.element, expects: text) {
            return .applied(method: "clipboard")
        }
        // 无法读回值的控件（如某些 Electron）粘贴可能已成功但不可验证：
        // 不报失败，但标注为未验证，交由上层按需处理。
        return .applied(method: "clipboard_unverified")
    }

    // MARK: - 剪贴板备份/恢复

    private struct SavedItem {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    private static func backupPasteboard(_ pb: NSPasteboard) -> [SavedItem] {
        var items: [SavedItem] = []
        guard let types = pb.types else { return items }
        for type in types {
            if let data = pb.data(forType: type) {
                items.append(SavedItem(type: type, data: data))
            }
        }
        return items
    }

    private static func restorePasteboard(_ pb: NSPasteboard, items: [SavedItem]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        for item in items {
            pb.setData(item.data, forType: item.type)
        }
    }
}
