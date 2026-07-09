import AppKit
import SwiftUI
import Carbon.HIToolbox
import ServiceManagement

/// 组装：胶囊面板 + SwiftUI 内容 + 光标轮询 hover + 动态窗口 + 全局热键 + 菜单栏。
final class CapsuleController: NSObject {
    private let state = AppState()
    private var panel: CapsulePanel!
    private var statusItem: NSStatusItem!
    private var escMonitor: Any?
    private var outsideClickMonitor: Any?
    private var pollTimer: Timer?
    private var shrinkWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var settingsWindow: NSWindow?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var debugFreeze = false   // 调试截图时锁住展开
    private var lastMode: CapsuleMode = .idle   // 大面板尺寸变化时锚定位置用
    private var panelDragStart: CGPoint?        // 拖标题挪窗口的起始原点
    private var panelDragStartMouse: NSPoint?   // 起始鼠标绝对位置(避免反馈抖动)
    private var snappedMidY: CGFloat?            // 小窗拖拽吸附后保留当前高度

    // hover 轮询累计
    private var dwell: Double = 0
    private var leaveAcc: Double = 0
    private let dt = 0.04
    private let dwellNeed = 0.15
    private let leaveNeed = 0.22
    private var hoverCapture = false          // 清零 hover 被动进入的 capture（区别于热键/点击主动进入）
    private var hoverCaptureTouched = false   // 被动 capture 后用户是否已开始写/编辑

    // 药丸/peek/capture 贴右屏缘(0)；大面板可拖动、浮空时需四周阴影余量(32)。须与 ContentView .padding(.trailing) 一致。
    private func contentInsetRight(_ mode: CapsuleMode) -> CGFloat { mode == .panel ? 32 : 0 }

    deinit {   // J: 对称卸载（单例当前不触发，但固化路径防未来重建时资源/回调堆积）
        pollTimer?.invalidate()
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
    }

    func start() {
        let hosting = NSHostingView(rootView: ContentView().environmentObject(state))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor   // 真透明，杜绝矩形背景/投影
        panel = CapsulePanel(contentRect: windowFrame(mode: .idle))
        panel.contentView = hosting
        panel.hasShadow = false                                  // 再确认：窗口不投矩形阴影，阴影只由 SwiftUI 圆角自绘
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = true            // idle 穿透
        panel.canBeginWindowDrag = { [weak self] point in self?.canBeginWindowDrag(at: point) ?? false }
        panel.canHandleHeaderDoubleClick = { [weak self] point in self?.canHandleHeaderDoubleClick(at: point) ?? false }
        panel.onHeaderDoubleClick = { [weak self] in self?.expandSmallWindowFromHeaderDoubleClick() }
        panel.onWindowDragChanged = { [weak self] in self?.windowDragChanged() }
        panel.onWindowDragEnded = { [weak self] in self?.endPanelDrag() }
        state.onLayout = { [weak self] mode in self?.applyLayout(mode: mode) }
        state.onPanelDragChanged = { [weak self] t in self?.movePanel(translation: t) }
        state.onPanelDragEnded = { [weak self] in self?.endPanelDrag() }
        state.onRequestKey = { [weak self] in self?.panel.makeKeyAndOrderFront(nil) }
        state.onPinnedChanged = { [weak self] pinned in self?.applyPinned(pinned) }
        state.onSettingsChanged = { [weak self] in
            self?.applyHotkeys()
            self?.applyLayout(mode: self?.state.mode ?? .idle)
            self?.rebuildMenu()
        }
        state.onOpenSettings = { [weak self] in self?.openSettingsWindow() }
        applyLayout(mode: .idle)
        applyPinned(state.windowPinned)
        if let text = NSPasteboard.general.string(forType: .string) {
            state.updateClipboard(text)
        }
        panel.orderFrontRegardless()

        applyHotkey()

        // Esc 取消
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self = self, e.keyCode == UInt16(kVK_Escape), self.state.mode != .idle else { return e }
            // C: 输入法组字中 → 放行，让 IME 先用 Esc 取消候选词，不塌胶囊
            if let tv = self.panel.firstResponder as? NSTextView, tv.hasMarkedText() { return e }
            // B: 行内编辑中 → 放行，交给 TextField.onExitCommand 取消本行编辑，不塌整个面板
            if self.state.isEditing { return e }
            // 其余展开态：Esc 收起
            self.state.setMode(.idle)
            return nil
        }

        // 点击胶囊外部（其它 app/桌面）→ 收起。展开态才生效；点胶囊内部是本窗口事件不触发全局监听。
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, !self.debugFreeze else { return }
            if self.state.mode == .idle {
                // idle 药丸是穿透的，其上的点击落进全局监听：命中药丸 → 展开大面板（A）
                if self.idlePillRect().contains(NSEvent.mouseLocation) {
                    self.state.enterPanel()
                    self.panel.makeKeyAndOrderFront(nil)
            }
            return
        }
        // 展开态：点胶囊外部 → 收起（内部点击是本窗口本地事件，不进全局监听）
            if self.state.windowPinned { return }
            self.state.isEditing = false
            self.state.setMode(.idle)
        }

        // 40ms 光标轮询：可靠的 hover 进入/离开（替代不可靠的 SwiftUI onHover）
        let t = Timer.scheduledTimer(withTimeInterval: dt, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        buildStatusItem()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.applyLayout(mode: self.state.mode)
        }

        // 调试：直接进某态 / 自测删除，便于截图核对
        if let dbg = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] {
            debugFreeze = true       // 调试态锁住展开（防轮询/外部点击收起）
            state.isEditing = true
            if dbg == "delete" {
                state.todos = [Todo(text: "样例待办 A"), Todo(text: "样例待办 B"), Todo(text: "样例待办 C")]
                state.enterPeek()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if let first = self.state.todos.first { self.state.complete(first) }
                }
            } else if dbg == "panel" {
                var pinned = Todo(text: "订下周三的会议室"); pinned.pinned = true
                state.todos = [Todo(text: "回复李工的方案评审"), Todo(text: "把周报草稿发出去"),
                               pinned, Todo(text: "看一下新版设计稿")]
                state.enterPanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let last = self.state.todos.last { self.state.complete(last) }
                    NSLog("PANEL active=\(self.state.active.count) completed=\(self.state.completed.count) mode=\(self.state.mode)")
                }
            } else if dbg == "multiadd" {
                state.todos = []
                state.enterCapture()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.state.draft = "连续录入第一条"; self.state.submit()
                    self.state.draft = "连续录入第二条"; self.state.submit()
                    NSLog("MULTIADD result mode=\(self.state.mode) count=\(self.state.count) draftEmpty=\(self.state.draft.isEmpty)")
                }
            } else if dbg == "logictest" {
                let a = Todo(text: "A"), b = Todo(text: "B"), c = Todo(text: "C"), d = Todo(text: "D")
                state.todos = [a, b, c, d]
                func A() -> String { state.active.map { $0.text }.joined(separator: ",") }
                func C() -> String { state.completed.map { $0.text }.joined(separator: ",") }
                func U() -> String { (state.undoItem?.text ?? "nil") + "/" + state.undoVerb }
                state.complete(a); state.complete(b)   // B1: 连续完成，各自独立、不互相覆盖
                NSLog("LT1 连完A,B → active=\(A()) completed=\(C()) undo=\(U())  期望 active=C,D completed=B,A undo=B/已完成")
                state.performUndo()                     // 撤销最近(B)，A 仍在沉底
                NSLog("LT2 撤销 → active=\(A()) completed=\(C()) undo=\(U())  期望 active含B completed=A undo=A/已完成")
                state.delete(c)                         // B4: 删除动词
                NSLog("LT3 删C → active=\(A()) undo=\(U())  期望 undo=C/已删除")
                state.performUndo()
                NSLog("LT4 撤销删 → active=\(A())  期望 含C")
                state.togglePin(d)                      // D 置顶
                let before = A()
                if let aa = state.todos.first(where: { $0.text == "A" }) {
                    state.moveActiveItem(aa.id, to: 0)   // B3: 非pin 想插到 index0(pin组) → 夹住不动
                }
                NSLog("LT5 跨组移A→0(应夹住) → active=\(A())  期望与之前同 \(before)")
            } else if dbg == "linkpanel" {
                state.todos = [Todo(text: "查一下 https://github.com/example/project 的 issue"),
                               Todo(text: "review PR www.example.com/pr/42"),
                               Todo(text: "普通待办没有链接")]
                state.enterPanel()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSLog("LINKPANEL active=\(self.state.active.count) mode=\(self.state.mode)")
                }
            } else if dbg == "collectpanel" {
                state.collects = [CollectItem(text: "灰度企业账号 admin@grayscale-corp.example.com 内网入口 https://portal.internal.example.com/login 备注：先连 VPN 再访问，密码每 90 天轮换一次"),
                                  CollectItem(text: "Gmail  user@example.com / hunter2", sensitive: true),
                                  CollectItem(text: "公司 WiFi 密码  office-5G-2024", sensitive: true),
                                  CollectItem(text: "https://design.system/tokens 速查")]
                state.collectDraft = "服务器登录步骤：\n1. 连 VPN（账号见上）\n2. ssh deploy@10.0.0.5\n3. cd /srv && ./up.sh"
                state.enterPanel()
                state.setPanelTab(.collect)
                panel.makeKeyAndOrderFront(nil)
            } else if dbg == "collecttest" {
                state.collects = []
                func L() -> String { state.collects.map { $0.text }.joined(separator: ",") }
                state.collectDraft = "Gmail user@x.com / pw123"; state.submitCollect()
                state.collectDraft = "会议纪要要点"; state.submitCollect()
                NSLog("CT1 存两条 → collects=\(L()) draftEmpty=\(state.collectDraft.isEmpty)  期望=会议纪要要点,Gmail... draftEmpty=true")
                if let g = state.collects.first(where: { $0.text.hasPrefix("Gmail") }) {
                    state.toggleCollectSensitive(g.id)
                    let s = state.collects.first { $0.id == g.id }?.sensitive ?? false
                    NSLog("CT2 标敏感 → sensitive=\(s)  期望=true")
                    state.updateCollectText(g.id, "Gmail user@x.com / NEWpw")
                    NSLog("CT3 改文本 → \(state.collects.first { $0.id == g.id }?.text ?? "nil")  期望含 NEWpw")
                    state.deleteCollect(g.id)
                    NSLog("CT4 删 → collects=\(L())  期望只剩 会议纪要要点")
                }
                // 持久化往返：save → load 还原（敏感位/文本不丢）
                CollectStore.save([CollectItem(text: "落盘条", sensitive: true)])
                let back = CollectStore.load()
                NSLog("CT5 落盘往返 → count=\(back.count) text=\(back.first?.text ?? "nil") sensitive=\(back.first?.sensitive ?? false)  期望 1/落盘条/true")
            } else {
                if state.todos.isEmpty {
                    state.todos = [Todo(text: "回复李工的方案评审"), Todo(text: "把周报草稿发出去"), Todo(text: "订下周三的会议室")]
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if dbg == "capture" { self.state.enterCapture(); self.panel.makeKeyAndOrderFront(nil) }
                    else { self.state.enterPeek() }
                }
            }
        }
    }

    // MARK: 光标轮询
    private func tick() {
        pollClipboard()
        let p = NSEvent.mouseLocation
        switch state.mode {
        case .idle:
            if idlePillRect().contains(p) {
                dwell += dt
                if dwell >= dwellNeed {
                    dwell = 0
                    state.enterCapture()
                    hoverCapture = true; hoverCaptureTouched = false
                    panel.makeKeyAndOrderFront(nil)
                    leaveAcc = 0
                }
            } else { dwell = 0 }
        case .peek:
            if debugFreeze || state.isEditing || expandedRect().insetBy(dx: -10, dy: -10).contains(p) {
                leaveAcc = 0
            } else {
                leaveAcc += dt
                if leaveAcc >= leaveNeed { leaveAcc = 0; state.setMode(.idle) }
            }
        case .capture:
            // 被动 hover 进入且用户尚未动手写 → 鼠标移开则自动收起、归还键盘焦点（消除"路过 hover 抢键盘且不放"，E）
            if hoverCapture {
                if !state.draft.isEmpty || state.isEditing { hoverCaptureTouched = true }
                if !hoverCaptureTouched {
                    if expandedRect().insetBy(dx: -10, dy: -10).contains(p) {
                        leaveAcc = 0
                    } else {
                        leaveAcc += dt
                        if leaveAcc >= leaveNeed { leaveAcc = 0; hoverCapture = false; state.setMode(.idle) }
                    }
                }
            }
        case .panel:
            break  // 大面板：只由 Enter/Esc/✕/点外退出，不因 hover 收
        }
    }

    // MARK: 命中矩形（屏幕坐标，bottom-left origin，与 NSEvent.mouseLocation 一致）
    private func contentRightX() -> CGFloat { panel.frame.maxX - contentInsetRight(state.mode) }
    private func contentLeftX() -> CGFloat { panel.frame.minX + contentInsetRight(state.mode) }
    private func idlePillRect() -> NSRect {
        let cy = panel.frame.midY
        if state.settings.position == .left {
            return NSRect(x: contentLeftX(), y: cy - CapsuleMetrics.idleH / 2,
                          width: CapsuleMetrics.idleW, height: CapsuleMetrics.idleH)
        }
        let rx = contentRightX()
        return NSRect(x: rx - CapsuleMetrics.idleW, y: cy - CapsuleMetrics.idleH / 2,
                      width: CapsuleMetrics.idleW, height: CapsuleMetrics.idleH)
    }
    private func expandedRect() -> NSRect {
        let cy = panel.frame.midY
        let h = CapsuleMetrics.expandedH(count: state.count)
        if state.settings.position == .left {
            return NSRect(x: contentLeftX(), y: cy - h / 2,
                          width: CapsuleMetrics.expandedW, height: h)
        }
        let rx = contentRightX()
        return NSRect(x: rx - CapsuleMetrics.expandedW, y: cy - h / 2,
                      width: CapsuleMetrics.expandedW, height: h)
    }

    // MARK: 窗口（动态：放大即时、收缩延迟，让 SwiftUI spring 主导视觉）
    private func windowFrame(mode: CapsuleMode) -> NSRect {
        let s = CapsuleMetrics.size(mode: mode, active: state.active.count, completed: state.completed.count,
                                    collect: state.collects.count, tab: state.panelTab)
        let leftPad: CGFloat = 44                    // 左阴影呼吸(软阴影完整在窗内)
        let ww = s.width + leftPad + contentInsetRight(mode)  // 窗宽随内容（面板更宽，阴影不被裁）
        let wh = s.height + 80                        // 上下各 40 阴影呼吸（竖直远离屏缘不会被裁）
        // 大面板已打开后的尺寸变化：锚定当前右上角(保留用户拖拽后的位置)，只改大小，不回弹右缘
        if mode == .panel, lastMode == .panel, let cur = panel?.frame {
            let anchored = NSRect(x: cur.maxX - ww, y: cur.maxY - wh, width: ww, height: wh)
            // F: 锚定结果与所有在线屏都无交集（外接屏被拔/分辨率变化）→ 回退默认右缘布局，避免面板遗留屏外找不回
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(anchored) }) {
                return anchored
            }
            let rvf = (panel?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            return NSRect(x: rvf.maxX - ww, y: rvf.midY - wh / 2, width: ww, height: wh)
        }
        let screen = panel?.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // 窗口右缘贴屏内右缘；idle/peek/capture inset 0=贴边(右阴影落屏外不可见、无悬空棱角)，大面板 inset 32 留浮空阴影余量
        let x = state.settings.position == .left ? vf.minX : vf.maxX - ww
        let midY = clampedMidY(snappedMidY ?? vf.midY, height: wh, visibleFrame: vf)
        return NSRect(x: x, y: midY - wh / 2, width: ww, height: wh)
    }

    /// 拖标题栏挪整个面板。用**绝对鼠标位置**算位移(NSEvent.mouseLocation)，
    /// 而非 SwiftUI 的 global translation——后者会随窗口移动而反馈，导致发抖。
    private func movePanel(translation _: CGSize) {
        shrinkWork?.cancel()   // K: 拖动期间取消挂起的延迟收缩 setFrame，避免把面板弹回旧位
        let m = NSEvent.mouseLocation
        if panelDragStart == nil { panelDragStart = panel.frame.origin; panelDragStartMouse = m }
        guard let o = panelDragStart, let sm = panelDragStartMouse else { return }
        panel.setFrameOrigin(CGPoint(x: o.x + (m.x - sm.x), y: o.y + (m.y - sm.y)))  // 同为屏幕坐标，无需 y 取反
        if state.mode == .panel { lastMode = .panel }   // 大窗后续增删条目锚定到挪后位置，不回弹
    }

    private func canBeginWindowDrag(at point: NSPoint) -> Bool {
        guard state.mode != .idle else { return false }
        let topBand = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - 86,
            width: panel.frame.width,
            height: 86
        )
        return topBand.contains(point)
    }

    private func canHandleHeaderDoubleClick(at point: NSPoint) -> Bool {
        guard state.mode == .peek || state.mode == .capture else { return false }
        let headerBand = NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - 78,
            width: panel.frame.width,
            height: 78
        )
        return headerBand.contains(point)
    }

    private func expandSmallWindowFromHeaderDoubleClick() {
        state.enterPanel()
        panel.makeKeyAndOrderFront(nil)
    }

    private func windowDragChanged() {
        shrinkWork?.cancel()
        if state.mode == .panel { lastMode = .panel }
    }

    private func endPanelDrag() {
        defer {
            panelDragStart = nil
            panelDragStartMouse = nil
        }
        guard state.mode != .panel else { return }
        let screen = screenForCurrentPanel()
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let side: CapsulePosition = panel.frame.midX < vf.midX ? .left : .right
        snappedMidY = clampedMidY(panel.frame.midY, height: panel.frame.height, visibleFrame: vf)
        guard state.settings.position != side else {
            applyLayout(mode: state.mode)
            return
        }
        state.updateSettings { $0.position = side }
    }

    private func screenForCurrentPanel() -> NSScreen? {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        return NSScreen.screens.first { $0.visibleFrame.contains(center) } ?? panel.screen ?? NSScreen.main
    }

    private func clampedMidY(_ midY: CGFloat, height: CGFloat, visibleFrame vf: NSRect) -> CGFloat {
        let half = height / 2
        guard vf.height > height else { return vf.midY }
        return min(max(midY, vf.minY + half), vf.maxY - half)
    }

    private func applyLayout(mode: CapsuleMode) {
        if mode != .capture { hoverCapture = false }   // 离开 capture 即清被动标记
        panel.ignoresMouseEvents = (mode == .idle)
        let target = windowFrame(mode: mode)
        shrinkWork?.cancel()
        if target.height < panel.frame.height - 1 {   // 变矮(收起/删条) → 延迟收，等 SwiftUI spring 收完，避免裁剪
            let w = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
            shrinkWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42, execute: w)
        } else {
            panel.setFrame(target, display: true)      // 变高/同高 → 即时，内容随后 spring 充满
        }
        lastMode = mode
    }

    // MARK: 菜单栏
    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "todo-capsule")
        rebuildMenu()
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        let summon = Settings.hotkeyOptions[min(max(0, state.settings.summonHotkeyIndex), Settings.hotkeyOptions.count - 1)]
        let cap = NSMenuItem(title: "记一条  \(summon.name)", action: #selector(captureAction), keyEquivalent: "")
        cap.target = self; menu.addItem(cap)
        let peek = NSMenuItem(title: "看清单", action: #selector(openPanelAction), keyEquivalent: "")
        peek.target = self; menu.addItem(peek)
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        menu.addItem(.separator())
        let hkItem = NSMenuItem(title: "热键", action: nil, keyEquivalent: "")
        let hkMenu = NSMenu()
        for (i, opt) in Settings.hotkeyOptions.enumerated() {
            let it = NSMenuItem(title: opt.name, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            it.target = self; it.representedObject = i
            it.state = (i == state.settings.summonHotkeyIndex) ? .on : .off
            hkMenu.addItem(it)
        }
        hkItem.submenu = hkMenu; menu.addItem(hkItem)
        let login = NSMenuItem(title: "开机自启", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = state.settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 todo-capsule", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    private func applyHotkey() { applyHotkeys() }
    private func applyHotkeys() {
        let summon = Settings.hotkeyOptions[min(max(0, state.settings.summonHotkeyIndex), Settings.hotkeyOptions.count - 1)]
        GlobalHotkey.shared.register(id: 1, keyCode: summon.keyCode, modifiers: summon.modifiers) { [weak self] in
            guard let self = self else { return }
            if self.state.mode == .panel {
                self.panel.makeKeyAndOrderFront(nil)
            } else {
                self.state.enterCapture()
                self.panel.makeKeyAndOrderFront(nil)
            }
        }

        let record = Settings.quickRecordHotkeyOptions[min(max(0, state.settings.quickRecordHotkeyIndex), Settings.quickRecordHotkeyOptions.count - 1)]
        GlobalHotkey.shared.register(id: 2, keyCode: record.keyCode, modifiers: record.modifiers) { [weak self] in
            self?.recordClipboardText()
        }
    }
    @objc private func captureAction() { state.enterCapture(); panel.makeKeyAndOrderFront(nil) }
    @objc private func openPanelAction() { state.enterPanel(); panel.makeKeyAndOrderFront(nil) }
    @objc private func settingsAction() { openSettingsWindow() }
    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard let i = sender.representedObject as? Int else { return }
        state.settings.summonHotkeyIndex = i
    }
    @objc private func toggleLaunchAtLogin() {
        state.settings.launchAtLogin.toggle()
    }

    private func applyPinned(_ pinned: Bool) {
        panel.level = pinned ? .statusBar : .floating
        panel.isFloatingPanel = true
        if pinned {
            panel.orderFrontRegardless()
        }
    }

    private func pollClipboard() {
        let board = NSPasteboard.general
        guard board.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = board.changeCount
        if let text = board.string(forType: .string) {
            state.updateClipboard(text)
        }
    }

    private func recordClipboardText() {
        let text = NSPasteboard.general.string(forType: .string) ?? state.lastClipboardText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.updateClipboard(text)
        state.addTodoLines(text, listId: defaultChecklistId)
        state.selectedListId = defaultChecklistId
        state.panelTab = .today
        state.enterPanel()
        panel.makeKeyAndOrderFront(nil)
    }

    private func openSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsView().environmentObject(state)
        let hosting = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered,
                           defer: false)
        win.title = "Todo Capsule 设置"
        win.contentView = hosting
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
