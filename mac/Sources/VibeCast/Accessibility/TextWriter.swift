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
    /// - writeMode: 写入策略（auto / axValue / clipboardPaste）。
    /// - allowSelectAllReplace: auto 模式下 AXValue 失败时是否允许 Cmd+A 全选替换。
    static func write(_ text: String, to binding: TargetBinding,
                      writeMode: WriteMode = .auto, allowSelectAllReplace: Bool = true) -> WriteResult {
        switch writeMode {
        case .clipboardPaste:
            // Electron/contenteditable（如 Notion AI 对话框）：直接走"输入框内全选+粘贴"。
            // Cmd+A 在已聚焦的单输入框内只选中该框内容，不会选中整页文档。
            return writeViaClipboard(text, to: binding)

        case .axValue:
            if AXSupport.isValueSettable(binding.element), AXSupport.setValue(binding.element, text),
               verify(binding.element, expects: text) {
                AXSupport.setSelectionToEnd(binding.element, length: text.count)
                return .applied(method: "axvalue")
            }
            return .failed("AXValue 直写失败（该目标限定 axvalue 模式）")

        case .auto:
            if AXSupport.isValueSettable(binding.element) {
                if AXSupport.setValue(binding.element, text), verify(binding.element, expects: text) {
                    AXSupport.setSelectionToEnd(binding.element, length: text.count)
                    return .applied(method: "axvalue")
                }
            }
            // AXValue 直写失败且不允许全选替换：拒绝，绝不冒险全选整页（PRD 14.2）。
            guard allowSelectAllReplace else {
                return .failed("AXValue 直写失败且该目标禁止全选替换（保护整页文档）")
            }
            return writeViaClipboard(text, to: binding)
        }
    }

    private static func verify(_ element: AXUIElement, expects text: String) -> Bool {
        // 读取回填值比对；某些控件归一化空白，故只要求前缀/全等其一。
        guard let current = AXSupport.value(of: element) else { return false }
        return current == text
    }

    // MARK: - 剪贴板降级（PRD 10.2）

    private static func writeViaClipboard(_ text: String, to binding: TargetBinding) -> WriteResult {
        // 合成键盘事件会发给"当前前台应用"。手机操作时目标常已不在前台，
        // 因此粘贴前必须把目标重新激活到前台（我们持有其 pid，激活是安全的）。
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != binding.pid {
            if let app = NSRunningApplication(processIdentifier: binding.pid) {
                app.activate(options: [])
                // 等待前台切换生效。
                var waited = 0.0
                while NSWorkspace.shared.frontmostApplication?.processIdentifier != binding.pid && waited < 0.6 {
                    Thread.sleep(forTimeInterval: 0.03); waited += 0.03
                }
            }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == binding.pid else {
            DiagnosticsLog.shared.log("clipboard write: 无法把目标激活到前台 pid=\(binding.pid)")
            return .failed("无法将目标置于前台（粘贴需要）")
        }

        // 全选输入框内容（Cmd+A 仅作用于已聚焦输入框）。
        guard KeyboardSynth.press(KeyShortcut(modifiers: ["command"], key: "a")) else {
            return .failed("无法发送全选")
        }
        Thread.sleep(forTimeInterval: 0.04)

        if text.isEmpty {
            // 清空：全选后按删除键。粘贴空串在 contenteditable 中不会删除选中内容。
            guard KeyboardSynth.press(KeyShortcut(modifiers: [], key: "delete")) else {
                return .failed("无法发送删除")
            }
            Thread.sleep(forTimeInterval: 0.06)
            return .applied(method: "clear")
        }

        let pasteboard = NSPasteboard.general
        let savedItems = backupPasteboard(pasteboard)
        defer { restorePasteboard(pasteboard, items: savedItems) }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.03)

        guard KeyboardSynth.press(KeyShortcut(modifiers: ["command"], key: "v")) else {
            return .failed("无法发送粘贴")
        }
        Thread.sleep(forTimeInterval: 0.12)

        // 验证：尽力读 AXValue 比对（Electron 常读不回，标注未验证但视为成功）。
        if verify(binding.element, expects: text) {
            return .applied(method: "clipboard")
        }
        DiagnosticsLog.shared.log("clipboard write: 已粘贴但无法读回验证 (Electron 常态)")
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
