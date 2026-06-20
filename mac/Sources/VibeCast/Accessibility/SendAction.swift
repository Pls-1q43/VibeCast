// 发送动作执行。PRD 13。
// 发送动作只能执行一次；无法判断是否已发送时返回 unknown，由用户决定是否重试。

import AppKit

enum SendActionResult {
    case sent
    case skipped(String)   // 仅同步模式：不执行发送
    case unknown(String)   // 无法确认是否已发送（PRD 13）
    case failed(String)
}

enum SendAction {

    /// 在已校验有效的绑定目标上执行发送。调用方必须先确保最终文本已写入且绑定有效。
    static func perform(profile: TargetProfile, binding: TargetBinding) -> SendActionResult {
        switch profile.sendMode {
        case .noneSyncOnly:
            // Notion 当前文本块等：仅同步，不发送（PRD 14.2）。
            return .skipped("该目标配置为仅同步，不执行发送")

        case .key, .customShortcut:
            // 合成按键发给前台应用；控制端常不在目标前台，发送前需重新激活目标，
            // 否则回车会发给错误的应用（危险）。
            guard ensureFrontmost(pid: binding.pid) else {
                return .failed("无法将目标置于前台（发送需要）")
            }
            let shortcut = profile.sendShortcut ?? .enter
            guard KeyboardSynth.press(shortcut) else {
                return .failed("发送快捷键映射失败: \(shortcut.key)")
            }
            return .sent

        case .accessibilityButton:
            guard let title = profile.sendButtonTitleContains, !title.isEmpty else {
                return .failed("未配置发送按钮标题")
            }
            if AXSupport.pressButton(pid: binding.pid, titleContains: title) {
                return .sent
            }
            // 未找到按钮：无法确认是否已发送，避免误判为成功。
            return .unknown("未找到标题含「\(title)」的发送按钮")
        }
    }

    /// 把目标进程激活到前台并等待生效。
    private static func ensureFrontmost(pid: pid_t) -> Bool {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        app.activate(options: [])
        var waited = 0.0
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid && waited < 0.6 {
            Thread.sleep(forTimeInterval: 0.03); waited += 0.03
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
}
