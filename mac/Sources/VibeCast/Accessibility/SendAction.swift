// 发送动作执行。PRD 13。
// 发送动作只能执行一次；无法判断是否已发送时返回 unknown，由用户决定是否重试。

import Foundation

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
}
