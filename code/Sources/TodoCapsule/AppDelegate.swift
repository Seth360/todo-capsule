import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CapsuleController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()      // accessory app 无主菜单 → ⌘C/⌘V/⌘X/⌘A 失灵；装标准 Edit 菜单让文本框/收藏支持复制粘贴
        controller = CapsuleController()
        controller?.start()
    }

    /// LSUIElement + nonactivatingPanel 不会显示菜单栏，但主菜单里的 Edit 项会为 key 窗口的文本框派发标准编辑快捷键。
    private func installEditMenu() {
        let mainMenu = NSMenu()
        // 第 0 项惯例是 App 菜单（即使 accessory 也保留占位，避免 Edit 被当成 App 菜单）
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // Accessory app：没有可关闭的主窗，保持常驻
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
