import AppKit

// todo-capsule —— 桌面边缘常驻"胶囊"待办（原生 SwiftUI + AppKit NSPanel）
// 入口：AppKit 生命周期（需要对 NSPanel 做精细控制，故不用 @main App）
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory：不占 Dock / Cmd-Tab，与主窗最小化解耦（D-006 / 研究 Part2 §3）
app.setActivationPolicy(.accessory)
app.run()
