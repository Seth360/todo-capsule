import SwiftUI
import AppKit

// MARK: 大面板「今天」tab + peek 一瞥 + 自定义拖拽重排 —— 从 ContentView.swift 拆出。
extension ContentView {

    // MARK: peek 一瞥（hover 出现、自动收）—— 只看 + 勾，右上可钉住面板
    var peekView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                smallListMenu
                Text("\(smallCurrentCount)")
                    .font(.tc(11.5, weight: .semibold)).foregroundStyle(accent)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.16)))
                Spacer()
                smallMoreMenu
                Button { withAnimation(anim) { state.enterPanel() } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.tc(11, weight: .semibold)).foregroundStyle(txt2)
                        .frame(width: 24, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("最大化")
                .pointingHandCursor()
            }
            .padding(.horizontal, 4).padding(.top, 2)
            .highPriorityGesture(TapGesture(count: 2).onEnded {
                withAnimation(anim) { state.enterPanel() }
            })
            .simultaneousGesture(smallWindowDragGesture)
            smallInputRow                                 // 常驻输入：跟随当前 tab 写入待办/收藏
            smallWindowListContent
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) {
            if state.shouldShowUpdateBanner {
                updateNoticeBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func peekRow(_ todo: Todo) -> some View {
        let editing = editingId == todo.id
        return HStack(spacing: 10) {
            Button { withAnimation(anim) { state.complete(todo) } } label: {
                Circle().strokeBorder(txt3, lineWidth: 1.6)
                    .frame(width: 18, height: 18).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            if editing {
                editTextArea(todo)
            } else {
                taggedText(todo.text).font(.tc(13)).foregroundStyle(txt)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            }
            if editing {
                editableTagPills(todo)
            } else {
                tagPills(todo.tags)
            }
            pinPill(todo)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { h in hoveredRow = h ? todo.id : (hoveredRow == todo.id ? nil : hoveredRow) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { startEdit(todo) })
        .contextMenu { todoContextMenu(todo) }
    }

    // MARK: 大面板（持久，点击打开、✕/Esc/点外关）—— 今天/收藏 双 tab
    var bigPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelHeader                                    // 顶栏(可拖) + 清单下拉 + 工具按钮
            Group {
                if state.panelTab == .today { todayPanelBody } else { collectPanelBody }
            }
            .padding(.horizontal, 16)                      // 输入框/列表内缩 16
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomLeading) {
            if state.mode == .panel { panelFooterTools }
        }
        .overlay(alignment: .bottom) {
            if state.mode == .panel, state.panelTab == .today, state.showingArchive {
                archiveFloatingPanel
            }
        }
        .overlay(alignment: .bottom) {
            if state.hasUndo {
                undoBar.zIndex(6)
            }
            else if state.panelTab == .collect, copiedFlash != nil { copiedToast }
        }
        .overlay(alignment: .bottom) {
            if state.shouldShowUpdateBanner {
                updateNoticeBanner
                    .padding(.bottom, state.hasUndo ? 38 : 0)
                    .zIndex(7)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("清空回收箱？", isPresented: $confirmingClearArchive) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                withAnimation(anim) { state.clearArchive() }
            }
        } message: {
            Text("确定后会删除回收箱里的已完成项目。")
        }
        .onChange(of: draggingId) { _, d in if d != nil { hoveredRow = nil } }   // 拖拽时清 hover，防控件残留错行
    }

    private var todayPanelBody: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelListTabs
            captureRow
            if state.active.isEmpty && state.completed.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(state.active) { panelRow($0) }
                        if !state.completed.isEmpty { completedSection }
                    }
                }
            }
        }
    }

    private var archiveFloatingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("回收箱", systemImage: "arrow.3.trianglepath")
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(txt)
                Text("\(state.completedArchive.count)")
                    .font(.tc(11, weight: .semibold))
                    .foregroundStyle(accent)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.16)))
                Spacer()
                Button {
                    confirmingClearArchive = true
                } label: {
                    Image(systemName: "trash")
                        .font(.tc(12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(txt3)
                .disabled(state.completedArchive.isEmpty)
                .help("清空回收箱")
                .pointingHandCursor()
                Button {
                    withAnimation(anim) { state.showingArchive = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.tc(12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(txt3)
                .help("关闭")
                .pointingHandCursor()
            }
            if state.completedArchive.isEmpty {
                Text("回收箱为空")
                    .font(.tc(12))
                    .foregroundStyle(txt3)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本周")
                        .font(.tc(11, weight: .semibold))
                        .foregroundStyle(txt3)
                        .padding(.horizontal, 2)
                    if archiveCurrentWeekItems.isEmpty {
                        Text("本周暂无完成项目")
                            .font(.tc(12))
                            .foregroundStyle(txt3)
                            .frame(maxWidth: .infinity, minHeight: 76)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(archiveCurrentWeekItems) { archiveRow($0) }
                            }
                        }
                        .frame(maxHeight: 204)
                    }
                    Button {
                        showingArchiveHistory = true
                    } label: {
                        Text("查看全部")
                            .font(.tc(12, weight: .semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(usesLightTheme ? Color.white.opacity(0.96) : Color(hex: 0x2C2C30).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(txt3.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(usesLightTheme ? 0.16 : 0.42), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .zIndex(3)
    }

    private func archiveRow(_ todo: Todo) -> some View {
        let hovered = hoveredRow == todo.id || (Self.forceHover && todo.id == archiveCurrentWeekItems.first?.id)
        return HStack(spacing: 10) {
            Button {
                withAnimation(anim) { state.restoreFromArchive(todo) }
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("恢复到待办")
            .pointingHandCursor()
            Text(linkedText(todo.text))
                .font(.tc(13))
                .foregroundStyle(txt2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            tagPills(todo.tags)
            Button {
                withAnimation(anim) { state.deleteFromArchive(todo) }
            } label: {
                Image(systemName: "trash")
                    .font(.tc(11, weight: .semibold))
                    .foregroundStyle(txt3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .help("永久删除")
            .pointingHandCursor()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovered ? Color.white.opacity(0.07) : subtleFill))
        .contentShape(Rectangle())
        .onHover { h in hoveredRow = h ? todo.id : (hoveredRow == todo.id ? nil : hoveredRow) }
        .contextMenu {
            Button { withAnimation(anim) { state.restoreFromArchive(todo) } } label: {
                Label("恢复到待办", systemImage: "arrow.uturn.backward.circle")
            }
            Button(role: .destructive) { withAnimation(anim) { state.deleteFromArchive(todo) } } label: {
                Label("永久删除", systemImage: "trash")
            }
        }
    }

    var archiveCurrentWeekItems: [Todo] {
        let interval = ArchiveDateGrouper.currentWeekInterval
        return state.completedArchive
            .filter { interval.contains($0.completedAt ?? $0.createdAt) }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    // 顶栏(全宽留白)是拖动区；标题下拉与右侧工具按钮单独可点。
    private var panelHeader: some View {
        HStack(spacing: 8) {
            Text("Todo Capsule")
                .font(.tc(15, weight: .semibold))
                .foregroundStyle(txt)
            Spacer(minLength: 8)
            headerIcon("doc.on.clipboard", help: "把剪贴板回填到待办") {
                withAnimation(anim) { state.importClipboardToTodos() }
            }
            .disabled(state.lastClipboardText.isEmpty)
            headerIcon("sparkles", help: "一键总结并复制") {
                state.makeSummary()
            }
            headerIcon(state.windowPinned ? "pin.fill" : "pin", help: state.windowPinned ? "取消钉住" : "钉住") {
                withAnimation(anim) { state.toggleWindowPinned() }
            }
            headerIcon("gearshape", help: "设置") {
                state.openSettings()
            }
            headerIcon("xmark", help: "关闭") {
                withAnimation(anim) { state.closePanel() }
            }
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { state.onPanelDragChanged?($0.translation) }
                .onEnded { _ in state.onPanelDragEnded?() }
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            withAnimation(anim) { state.enterCapture() }
        })
    }

    var panelListTabs: some View {
        HStack(spacing: 10) {
            ForEach(state.lists) { list in
                panelListTabButton(
                    title: list.name,
                    count: state.active(in: list.id).count,
                    isOn: state.panelTab == .today && state.selectedListId == list.id,
                    dot: list.id == defaultChecklistId ? accent : listColor(list.id)
                ) {
                    withAnimation(anim) { state.selectList(list.id) }
                }
            }
            panelListTabButton(
                title: "收藏",
                count: state.collects.count,
                isOn: state.panelTab == .collect,
                dot: Color(hex: 0xB692FF)
            ) {
                withAnimation(anim) { state.setPanelTab(.collect) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func panelListTabButton(title: String, count: Int, isOn: Bool, dot: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(isOn ? txt : txt2)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.tc(11, weight: .semibold))
                    .foregroundStyle(isOn ? accent : txt3)
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill((isOn ? accent : txt3).opacity(isOn ? 0.16 : 0.10)))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 108)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? subtleFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func listColor(_ id: String) -> Color {
        let palette: [UInt32] = [0xFFB07C, 0x86D4FF, 0xC69CFF, 0xFFD166, 0x7DE2D1, 0xFF8FAB]
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }

    private var listMenu: some View {
        Menu {
            ForEach(state.lists) { list in
                Button {
                    withAnimation(anim) { state.selectList(list.id) }
                } label: {
                    Label(list.name, systemImage: state.panelTab == .today && state.selectedListId == list.id ? "checkmark" : "list.bullet")
                }
            }
            Divider()
            Button {
                withAnimation(anim) { state.setPanelTab(.collect) }
            } label: {
                Label("收藏", systemImage: state.panelTab == .collect ? "checkmark" : "bookmark")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.tc(8, weight: .semibold))
                    .foregroundStyle(txt2)
                Text(state.panelTab == .collect ? "收藏" : state.currentList.name)
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(txt)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointingHandCursor()
    }

    private func headerIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.tc(12, weight: .semibold))
                .foregroundStyle(txt3)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHandCursor()
    }

    private var panelFooterTools: some View {
        HStack(spacing: 8) {
            footerIcon(state.showingArchive ? "arrow.3.trianglepath.circle.fill" : "arrow.3.trianglepath", help: "查看回收箱") {
                withAnimation(anim) { state.toggleArchiveView() }
            }
            footerIcon("folder", help: "打开 Markdown 所在目录") {
                state.openMarkdownFolder()
            }
        }
        .padding(.leading, 18)
        .padding(.bottom, 12)
    }

    private func footerIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.tc(12, weight: .semibold))
                .foregroundStyle(txt3)
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHandCursor()
    }

    // 旧分段切换保留为内部构件，目前入口改为标题下拉。
    private var tabSwitcher: some View {
        HStack(spacing: 6) {
            tabButton("今天", count: state.count, tab: .today)
            tabButton("收藏", count: state.collects.count, tab: .collect)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.bottom, 2)
    }
    private func tabButton(_ title: String, count: Int, tab: PanelTab) -> some View {
        let on = state.panelTab == tab
        return Button { withAnimation(anim) { state.setPanelTab(tab) } } label: {
            HStack(spacing: 5) {
                Text(title).font(.tc(14, weight: .semibold))
                Text("\(count)").font(.tc(11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(on ? accent : txt3)
            }
            .foregroundStyle(on ? txt : txt3)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(on ? Color.white.opacity(0.08) : .clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("已完成")
                .font(.tc(11, weight: .medium)).foregroundStyle(txt3)
                .padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 3)
            ForEach(state.completed) { doneRow($0) }
        }
    }

    private func doneRow(_ todo: Todo) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.tc(10, weight: .bold)).foregroundStyle(.white)
            }
            .frame(width: 26, height: 26)
            Text(linkedText(todo.text))
                .font(.tc(13)).foregroundStyle(txt3)
                .strikethrough(true, color: txt3)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
    }

    // 大面板行：圆勾 + 文字/行内编辑 + hover 才出(置顶/删除) + 拖拽重排
    private func panelRow(_ todo: Todo) -> some View {
        let hovered = (hoveredRow == todo.id || (Self.forceHover && todo.id == state.active.first?.id)) && draggingId == nil
        let idx = state.active.firstIndex(where: { $0.id == todo.id }) ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            panelRowMainLine(todo, hovered: hovered, idx: idx)
        }
        .onHover { h in hoveredRow = h ? todo.id : (hoveredRow == todo.id ? nil : hoveredRow) }
        .contextMenu { todoContextMenu(todo) }
    }

    private func panelRowMainLine(_ todo: Todo, hovered: Bool, idx: Int) -> some View {
        let editing = editingId == todo.id
        return HStack(spacing: 10) {
            Button { withAnimation(anim) { state.complete(todo) } } label: {
                Circle().strokeBorder(txt3, lineWidth: 1.6)
                    .frame(width: 18, height: 18)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if editing {
                editTextArea(todo)
            } else {
                taggedText(todo.text)
                    .font(.tc(13)).foregroundStyle(txt).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if editing {
                editableTagPills(todo)
            } else {
                tagPills(todo.tags)
            }
            pinPill(todo)
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(editing ? accent.opacity(0.10)
                      : draggingId == todo.id ? Color.white.opacity(0.09)
                      : (hovered ? Color.white.opacity(0.05) : Color.white.opacity(0.001)))
        )
        .scaleEffect(draggingId == todo.id ? 1.03 : 1)
        .shadow(color: draggingId == todo.id ? .black.opacity(0.45) : .clear,
                radius: draggingId == todo.id ? 12 : 0, x: 0, y: draggingId == todo.id ? 6 : 0)
        .offset(y: rowYOffset(todo, at: idx))
        .zIndex(draggingId == todo.id ? 1 : 0)
        .gesture(reorderGesture(todo, at: idx))
        .simultaneousGesture(TapGesture(count: 2).onEnded { startEdit(todo) })
        .animation(nil, value: hovered)
    }

    // MARK: 自定义拖拽重排（被拖行裸绑偏移=跟手；其它行 spring 实时让位；落下安定 + 触觉）
    private func reorderGesture(_ todo: Todo, at idx: Int) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { v in
                if draggingId == nil {
                    withAnimation(.snappy(duration: 0.18)) { draggingId = todo.id }
                    draggingFrom = idx; targetIndex = idx
                    Haptic.bump()
                }
                dragOffset = v.translation.height                          // 裸绑，无动画 → 跟手
                let from = draggingFrom ?? idx
                let raw = from + Int((v.translation.height / rowH).rounded())
                let t = clampToGroup(raw, pinned: todo.pinned)
                if t != targetIndex {
                    withAnimation(.snappy(duration: 0.22)) { targetIndex = t }  // 其它行 spring 让位
                    Haptic.bump()
                }
            }
            .onEnded { _ in
                if let id = draggingId, let t = targetIndex { state.moveActiveItem(id, to: t) }
                Haptic.bump()
                withAnimation(.snappy(duration: 0.26)) {
                    draggingId = nil; draggingFrom = nil; dragOffset = 0; targetIndex = nil
                }
            }
    }
    private func clampToGroup(_ raw: Int, pinned: Bool) -> Int {
        let act = state.active
        let lo = act.firstIndex(where: { $0.pinned == pinned }) ?? 0
        let hi = act.lastIndex(where: { $0.pinned == pinned }) ?? (act.count - 1)
        return min(max(raw, lo), hi)
    }
    private func rowYOffset(_ todo: Todo, at idx: Int) -> CGFloat {
        if todo.id == draggingId { return dragOffset }
        guard draggingId != nil, let from = draggingFrom, let to = targetIndex else { return 0 }
        if from < to && idx > from && idx <= to { return -rowH }   // 被拖行下移 → 让位上移
        if to < from && idx >= to && idx < from { return rowH }    // 被拖行上移 → 让位下移
        return 0
    }
}
