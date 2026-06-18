// 目标聚焦与绑定校验。PRD 9.2 / 9.3 / 16.2 / 16.3。
// 安全核心：成功聚焦后记录绑定；后续写入/发送前必须校验绑定仍有效，
// 否则暂停同步、报「目标失焦」，绝不向任意焦点盲写（PRD 3.4 / 10.3）。

import ApplicationServices
import AppKit

/// 一次成功聚焦后记录的目标绑定。
struct TargetBinding {
    let targetId: TargetId
    let sessionId: String
    let pid: pid_t
    let bundleId: String
    let element: AXUIElement
    let role: String?
}

enum FocusOutcome {
    case focused(TargetBinding)
    case appNotRunning
    case appLaunchFailed(String)
    case noPermission
    case notFocused(String)
}

enum FocusController {

    /// 激活并聚焦目标，返回绑定或失败原因。应在后台队列调用（含同步等待）。
    static func focus(targetId: TargetId, sessionId: String, profile: TargetProfile) -> FocusOutcome {
        guard AccessibilityPermission.isGranted else { return .noPermission }

        // 1) 激活应用
        let act = AppActivator.activate(bundleId: profile.bundleId,
                                        launchIfNotRunning: profile.launchIfNotRunning,
                                        timeoutMs: profile.focusWaitMs * 4)
        let pid: pid_t
        switch act {
        case .activated(let p): pid = p
        case .notRunning: return .appNotRunning
        case .launchFailed(let m): return .appLaunchFailed(m)
        case .timeout: return .notFocused("应用激活超时")
        }

        // 2) 执行聚焦策略
        switch profile.focusMode {
        case .shortcut:
            if let sc = profile.focusShortcut {
                _ = KeyboardSynth.press(sc)
                Thread.sleep(forTimeInterval: Double(profile.focusWaitMs) / 1000.0)
            }
        case .preserveLastFocus:
            // 直接使用应用当前焦点，不额外操作。
            break
        case .accessibility, .custom:
            // M3-2 / 二期实现；此处先回退为 preserveLastFocus 行为。
            break
        }

        // 3) 读取当前聚焦元素并校验
        guard let element = AXSupport.focusedElement(pid: pid) else {
            return .notFocused("未取得聚焦控件")
        }
        guard AXSupport.isEditableText(element) else {
            return .notFocused("当前聚焦控件不可编辑")
        }
        let role = AXSupport.role(of: element)
        let binding = TargetBinding(targetId: targetId, sessionId: sessionId,
                                    pid: pid, bundleId: profile.bundleId,
                                    element: element, role: role)
        return .focused(binding)
    }

    /// 校验绑定是否仍然有效：应用仍在前台 + 焦点元素未变。PRD 9.3。
    static func validate(_ binding: TargetBinding) -> Bool {
        // 应用仍在前台？
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == binding.pid else {
            return false
        }
        // 当前焦点元素仍是绑定元素？
        guard let current = AXSupport.focusedElement(pid: binding.pid) else { return false }
        // AXUIElement 支持 == 比较（CFEqual）。
        return CFEqual(current, binding.element)
    }
}
