import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: CapsuleController?
    private var didReceiveInitialActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = CapsuleController()
        installMainMenu()
        controller?.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.openLargePanelFromDock()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 跳过首次启动激活；之后从 Dock 回到本应用时统一打开大窗。
        guard didReceiveInitialActivation else {
            didReceiveInitialActivation = true
            return
        }
        controller?.openLargePanelFromDock()
    }

    /// 安装标准 App / Edit 菜单；Edit 菜单也让 nonactivatingPanel 中的文本框支持系统编辑快捷键。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "todo-capsule"
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        let about = NSMenuItem(title: "关于 " + appName, action: #selector(CapsuleController.aboutAction), keyEquivalent: "")
        about.target = controller
        appMenu.addItem(about)
        let settings = NSMenuItem(title: "设置…", action: #selector(CapsuleController.settingsAction), keyEquivalent: ",")
        settings.target = controller
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 " + appName, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appItem.submenu = appMenu
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
