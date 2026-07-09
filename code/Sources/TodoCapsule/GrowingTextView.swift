import AppKit
import SwiftUI

/// 多行自增长输入框（独立 NSTextView，不蹭窗口共享 field editor）。
/// 原因：SwiftUI TextField(axis:.vertical) 在 nonactivatingPanel 里复用 field editor，
/// Return 被当单行提交（表现为"全选"）而非换行。这里用自有 NSTextView：
/// Return=换行、⌘Return=提交、随内容增长（封顶 maxLines 后内部滚动）。
struct GrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var focusTick: Int                 // 值变化即请求聚焦
    var maxLines: Int = 8
    var onSubmit: () -> Void = {}      // ⌘Return
    var onEndEditing: () -> Void = {}  // 失焦（编辑态用它落定）
    var onCancel: () -> Void = {}      // Esc（编辑态用它取消）

    private let lineH: CGFloat = 18

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.font = .tc(13)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textColor = NSColor(white: 0.949, alpha: 1)                                   // ≈ 0xF2F2F4
        tv.insertionPointColor = NSColor(red: 0.196, green: 0.82, blue: 0.345, alpha: 1) // accent
        tv.textContainerInset = NSSize(width: 0, height: 1)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]

        scroll.documentView = tv
        context.coordinator.tv = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        if context.coordinator.lastFocusTick != focusTick {
            context.coordinator.lastFocusTick = focusTick
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
        DispatchQueue.main.async { context.coordinator.recalc() }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        weak var tv: NSTextView?
        var lastFocusTick: Int

        // 起始落后一拍：新建的字段（如刚进入编辑态）首个 updateNSView 即会兑现已挂起的聚焦请求，
        // 否则 focusTick 在视图创建前自增 → 协调器初始即"追平" → 永不聚焦（编辑框打不了字的根因）。
        init(_ p: GrowingTextView) { parent = p; lastFocusTick = p.focusTick - 1 }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            recalc()
        }

        func textDidEndEditing(_ n: Notification) { parent.onEndEditing() }

        func recalc() {
            guard let tv = tv, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let h = min(max(used, parent.lineH), CGFloat(parent.maxLines) * parent.lineH)
            if abs(parent.height - h) > 0.5 { parent.height = h }
        }

        // Return=换行；⌘Return=提交；Esc=取消（仅编辑态会走到——输入态 Esc 被上层 escMonitor 先消费收面板）。
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                if (NSApp.currentEvent?.modifierFlags ?? []).contains(.command) {
                    parent.onSubmit(); return true
                }
                tv.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel(); return true
            }
            return false
        }
    }
}
