import AppKit

/// 胶囊窗口本体。落地研究报告 Part 2 §3 的关键 NSPanel 机制：
/// non-activating（不抢焦点但能输入）+ 跨所有 Space + 浮于全屏（best-effort）+ 透明自绘。
final class CapsulePanel: NSPanel, NSWindowDelegate {
    var canBeginWindowDrag: ((NSPoint) -> Bool)?
    var canHandleHeaderDoubleClick: ((NSPoint) -> Bool)?
    var onHeaderDoubleClick: (() -> Void)?
    var onWindowDragChanged: (() -> Void)?
    var onWindowDragEnded: (() -> Void)?
    var onCloseRequested: (() -> Void)?
    var onMiniaturizeRequested: (() -> Void)?

    private(set) var isLargeWorkspace = false

    private var possibleWindowDrag = false
    private var isWindowDragging = false
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var resizeObserver: NSObjectProtocol?
    private var enforcingSizeLimits = false
    private var lastAcceptedLargeFrame: NSRect?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar                       // 小胶囊高于普通窗口
        // 跨普通 Space + 浮于他人全屏(best-effort, F5) + Mission Control 不被当普通窗平移
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 只在需要时成 key（点输入框才收键盘）→ 不抢焦点又能写（D-002/D-006）
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true                         // 交给 AppKit 在透明窗口外绘制投影，避免圆角阴影被矩形边界裁切
        isMovableByWindowBackground = false   // 由 controller 在 panel 态打开
        isMovable = true                       // 允许移动（仅 panel 态经 movableByBackground 触发）
        hidesOnDeactivate = false
        worksWhenModal = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        delegate = self
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.enforceLargeWorkspaceSizeLimits()
        }
    }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    override var canBecomeKey: Bool { true }     // 允许输入框收键盘
    override var canBecomeMain: Bool { isLargeWorkspace }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        guard isLargeWorkspace else { return frameSize }
        return NSSize(
            width: min(max(frameSize.width, contentMinSize.width), contentMaxSize.width),
            height: min(max(frameSize.height, contentMinSize.height), contentMaxSize.height)
        )
    }

    func configurePresentation(largeWorkspace: Bool) {
        guard isLargeWorkspace != largeWorkspace else { return }
        isLargeWorkspace = largeWorkspace
        if largeWorkspace {
            // 大窗继续使用无边框窗口；红黄绿由 SwiftUI 放在内容内部，避免系统标题栏出现在内容之外。
            styleMask = [.borderless, .resizable]
            isFloatingPanel = false
            level = .normal
            collectionBehavior = [.managed]
            becomesKeyOnlyIfNeeded = false
            minSize = CapsuleMetrics.panelMinSize
            maxSize = CapsuleMetrics.panelMaxSize
            contentMinSize = CapsuleMetrics.panelMinSize
            contentMaxSize = CapsuleMetrics.panelMaxSize
            lastAcceptedLargeFrame = frame
        } else {
            styleMask = [.nonactivatingPanel, .borderless]
            isFloatingPanel = true
            level = .statusBar
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            becomesKeyOnlyIfNeeded = true
            minSize = .zero
            maxSize = NSSize(width: 10_000, height: 10_000)
            contentMinSize = .zero
            contentMaxSize = NSSize(width: 10_000, height: 10_000)
            lastAcceptedLargeFrame = nil
        }
        isOpaque = false
        backgroundColor = .clear
        contentView?.wantsLayer = true
        contentView?.layer?.isOpaque = false
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        hasShadow = true
        invalidateShadow()
    }

    private func enforceLargeWorkspaceSizeLimits() {
        guard isLargeWorkspace, !enforcingSizeLimits else { return }
        let current = frame
        let width = min(max(current.width, CapsuleMetrics.panelMinSize.width), CapsuleMetrics.panelMaxSize.width)
        let height = min(max(current.height, CapsuleMetrics.panelMinSize.height), CapsuleMetrics.panelMaxSize.height)

        guard abs(width - current.width) > 0.5 || abs(height - current.height) > 0.5 else {
            lastAcceptedLargeFrame = current
            return
        }

        var target = current
        if let previous = lastAcceptedLargeFrame {
            if abs(current.maxX - previous.maxX) < abs(current.minX - previous.minX) {
                target.origin.x = current.maxX - width
            }
            if abs(current.maxY - previous.maxY) < abs(current.minY - previous.minY) {
                target.origin.y = current.maxY - height
            }
        }
        target.size = NSSize(width: width, height: height)
        enforcingSizeLimits = true
        super.setFrame(target, display: true)
        enforcingSizeLimits = false
        lastAcceptedLargeFrame = target
    }

    override func performClose(_ sender: Any?) {
        guard isLargeWorkspace else {
            super.performClose(sender)
            return
        }
        onCloseRequested?()
    }

    override func miniaturize(_ sender: Any?) {
        guard isLargeWorkspace else {
            super.miniaturize(sender)
            return
        }
        onMiniaturizeRequested?()
    }
    // 允许窗口延伸到屏幕外：右阴影的裁切落到屏外(不可见)，避免软阴影被窗口矩形裁出棱角
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isLargeWorkspace {
                NSApp.activate(ignoringOtherApps: true)
                makeKeyAndOrderFront(nil)
            }
            let mouse = NSEvent.mouseLocation
            if event.clickCount == 2, canHandleHeaderDoubleClick?(mouse) == true {
                possibleWindowDrag = false
                isWindowDragging = false
                dragStartMouse = nil
                dragStartOrigin = nil
                onHeaderDoubleClick?()
                return
            }
            possibleWindowDrag = canBeginWindowDrag?(mouse) ?? false
            isWindowDragging = false
            dragStartMouse = mouse
            dragStartOrigin = frame.origin
            super.sendEvent(event)
        case .leftMouseDragged:
            guard possibleWindowDrag,
                  let startMouse = dragStartMouse,
                  let startOrigin = dragStartOrigin else {
                super.sendEvent(event)
                return
            }

            let mouse = NSEvent.mouseLocation
            let dx = mouse.x - startMouse.x
            let dy = mouse.y - startMouse.y
            if !isWindowDragging, hypot(dx, dy) < 4 {
                super.sendEvent(event)
                return
            }

            isWindowDragging = true
            setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
            onWindowDragChanged?()
        case .leftMouseUp:
            let shouldEndDrag = isWindowDragging
            possibleWindowDrag = false
            isWindowDragging = false
            dragStartMouse = nil
            dragStartOrigin = nil
            if shouldEndDrag {
                onWindowDragEnded?()
            } else {
                super.sendEvent(event)
            }
        default:
            super.sendEvent(event)
        }
    }
}
