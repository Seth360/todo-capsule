import AppKit

/// 胶囊窗口本体。落地研究报告 Part 2 §3 的关键 NSPanel 机制：
/// non-activating（不抢焦点但能输入）+ 跨所有 Space + 浮于全屏（best-effort）+ 透明自绘。
final class CapsulePanel: NSPanel {
    var canBeginWindowDrag: ((NSPoint) -> Bool)?
    var canHandleHeaderDoubleClick: ((NSPoint) -> Bool)?
    var onHeaderDoubleClick: (() -> Void)?
    var onWindowDragChanged: (() -> Void)?
    var onWindowDragEnded: (() -> Void)?

    private var possibleWindowDrag = false
    private var isWindowDragging = false
    private var dragStartMouse: NSPoint?
    private var dragStartOrigin: NSPoint?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar                       // 高于普通窗口
        // 跨普通 Space + 浮于他人全屏(best-effort, F5) + Mission Control 不被当普通窗平移
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // 只在需要时成 key（点输入框才收键盘）→ 不抢焦点又能写（D-002/D-006）
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear                 // SwiftUI 自绘圆角 + 投影
        hasShadow = false
        isMovableByWindowBackground = false   // 由 controller 在 panel 态打开
        isMovable = true                       // 允许移动（仅 panel 态经 movableByBackground 触发）
        hidesOnDeactivate = false
        worksWhenModal = true
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }     // 允许输入框收键盘
    override var canBecomeMain: Bool { false }   // 但绝不成为 main（不抢前台）
    // 允许窗口延伸到屏幕外：右阴影的裁切落到屏外(不可见)，避免软阴影被窗口矩形裁出棱角
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
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
