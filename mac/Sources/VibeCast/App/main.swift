// VibeCast 菜单栏服务入口。
// 以 LSUIElement（无 Dock 图标）方式运行，仅在状态栏提供入口。

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 菜单栏 App，不在 Dock 显示

let delegate = AppDelegate()
app.delegate = delegate
app.run()
