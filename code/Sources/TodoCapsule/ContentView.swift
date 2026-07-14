import SwiftUI
import AppKit

/// 单一形变胶囊（Approach B）：idle ↔ peek ↔ capture，SwiftUI spring 弹性形变。
/// 核心：形态壳 + capture 速记 + idle 药丸 + 共享文本渲染(linkedText/taggedText) + 行内编辑。
/// 大面板/收藏夹叠加层分别见 ContentView+Panel / +Collect；共用尺寸/色板/触觉在 CapsuleChrome。
/// 部分存储属性与 view 成员访问级为 internal（非 private），是为了让上述 extension 文件能触达——同模块内部，无外部 API 面。
struct ContentView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var inputFocused: Bool
    @FocusState var collectInputFocused: Bool
    @FocusState var editFocused: Bool
    @FocusState var workspaceDraftFocused: Bool
    @FocusState var workspaceTodoEditFocused: UUID?
    @State var editingId: UUID?
    @State var editText = ""
    @State var hoveredRow: UUID?      // 大面板：hover 才出控件
    // 收藏夹
    @State var collectFocusTick = 0          // 自增即请求聚焦收藏输入框（GrowingTextView）
    @State var collectInputHeight: CGFloat = 18
    @State var collectEditFocusTick = 0      // 自增即请求聚焦收藏编辑框
    @State var collectEditHeight: CGFloat = 18
    @State var editingCollectId: UUID?
    @State var editCollectText = ""
    @State var revealedId: UUID?      // 当前临时显形的敏感收藏
    @State var copiedFlash: UUID?     // 刚复制 → 底部「已复制」提示
    @State var confirmingClearArchive = false
    @State var showingArchiveHistory = false
    @State var workspaceDestination: WorkspaceDestination = .list(defaultChecklistId)
    @State var selectedSummaryID: UUID?
    @State var hoveredWorkspaceSummaryID: UUID?
    @State var hoveredWorkspaceListID: String?
    @State var hoveredWorkspaceTagID: String?
    @State var hoveredWorkspaceNavTitle: String?
    @State var workspaceListSectionHovered = false
    @State var workspaceTagHeaderHovered = false
    @State var mergingTag: TodoTag?
    @State var editingWorkspaceTag: TodoTag?
    @State var editingWorkspaceList: Checklist?
    @State var creatingWorkspaceList = false
    @State var pendingWorkspaceDeletion: WorkspaceDeletionTarget?
    @State var hoveredWorkspaceTodoID: UUID?
    @State var editingWorkspaceTodoID: UUID?
    @State var workspaceTodoEditText = ""
    @State var workspaceCompletedSearch = ""
    @State var workspaceCompletedTag: String?
    @State var hoveredWorkspaceCompletedID: UUID?
    @StateObject var workspaceOverlayState = WorkspaceOverlayState()
    @State var hoveredSummaryTemplateMenuID: String?
    @State var workspaceTagSuggestionsDismissed = false
    // 拖拽重排（自定义 DragGesture：被拖行裸绑偏移跟手，其它行 spring 实时让位）
    @State var draggingId: UUID?
    @State var draggingFrom: Int?
    @State var dragOffset: CGFloat = 0
    @State var targetIndex: Int?
    let rowH: CGFloat = 34

    var usesLightTheme: Bool {
        switch state.settings.theme {
        case .light: return true
        case .dark: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
        }
    }
    var preferredScheme: ColorScheme? {
        switch state.settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
    var cap: Color { usesLightTheme ? Color(hex: 0xF7F7F8) : Color(hex: 0x1C1C1E) }
    var panel: Color { usesLightTheme ? Color(hex: 0xFFFFFF) : Color(hex: 0x222225) }
    var txt: Color { usesLightTheme ? Color(hex: 0x1D1D1F) : Color(hex: 0xF2F2F4) }
    var txt2: Color { usesLightTheme ? Color(hex: 0x5C5C62) : Color(hex: 0x9B9BA1) }
    var txt3: Color { usesLightTheme ? Color(hex: 0x85858B) : Color(hex: 0x6E6E74) }
    var accent: Color { CapsuleDesign.primary }
    var subtleFill: Color { usesLightTheme ? Color.black.opacity(0.045) : Color.white.opacity(0.04) }

    // 大面板/收藏夹 hover 控件在无真实鼠标的调试环境下强制展开（截图核对用）
    static let forceHover = ProcessInfo.processInfo.environment["TC_FORCE_HOVER"] != nil

    // 弹性 spring（带过冲），reduce-motion 降级为平滑无位移
    var anim: Animation {
        reduceMotion ? .easeOut(duration: 0.16)
                     : .spring(response: 0.36, dampingFraction: 0.66)
    }
    private var radius: CGFloat { state.mode == .idle ? CapsuleMetrics.idleW / 2 : 18 }
    private var capSize: CGSize {
        let smallCount = state.panelTab == .collect && state.mode != .panel ? state.collects.count : state.active.count
        return CapsuleMetrics.size(mode: state.mode, active: smallCount, completed: state.completed.count,
                            collect: state.collects.count, tab: state.panelTab)
    }

    var body: some View {
        capsule
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.settings.position == .left ? .leading : .trailing)
            .padding(state.settings.position == .left ? .leading : .trailing, 0)
            .onChange(of: state.mode) { _, m in
                if m == .panel {                                 // 大面板打开即聚焦当前 tab 的输入框
                    if state.panelTab == .collect { collectInputFocused = true } else { inputFocused = true }
                    DispatchQueue.main.async { workspaceDraftFocused = true }
                } else {
                    inputFocused = (m == .capture)
                    collectInputFocused = false
                    workspaceDraftFocused = false
                }
                if m == .idle {
                    if let id = editingId {
                        state.updateText(id, editText)
                    }
                    editingId = nil; editingCollectId = nil; editingWorkspaceTodoID = nil; state.isEditing = false
                }
            }
            .onChange(of: state.panelTab) { _, t in              // 切 tab → 焦点跟到对应输入框
                guard state.mode == .panel else { return }
                if t == .collect {
                    collectInputFocused = true
                    state.onRequestKey?()
                } else {
                    inputFocused = true
                }
            }
            .preferredColorScheme(preferredScheme)
            .tint(CapsuleDesign.primary)
            .sheet(isPresented: $showingArchiveHistory) {
                ArchiveHistoryView()
                    .environmentObject(state)
                    .preferredColorScheme(preferredScheme)
            }
    }

    private var capsule: some View {
        ZStack {
            switch state.mode {
            case .idle:    idleFace.transition(.opacity)
            case .peek:    peekView.transition(.opacity)
            case .panel:   bigPanel.transition(.opacity)
            case .capture: expanded.transition(.opacity)
            }
        }
        .overlay(alignment: .center) {
            summaryToast
        }
        .frame(
            width: state.mode == .panel ? nil : capSize.width,
            height: state.mode == .panel ? nil : capSize.height
        )
        .frame(
            maxWidth: state.mode == .panel ? .infinity : nil,
            maxHeight: state.mode == .panel ? .infinity : nil
        )
        .modifier(CapsuleSurface(radius: radius, fill: state.mode == .idle ? cap : panel))
        .animation(anim, value: state.mode)
        .animation(anim, value: state.count)
        .animation(anim, value: state.completed.count)
        .animation(anim, value: state.collects.count)
        .animation(anim, value: state.panelTab)
        .animation(anim, value: state.summaryToast)
    }

    // MARK: idle —— 利落竖药丸
    private var idleFace: some View {
        VStack(spacing: 6) {
            // 状态点：有待办=accent 亮，无=暗灰
            Circle()
                .fill(state.count == 0 ? txt3.opacity(0.5) : accent)
                .frame(width: 5, height: 5)
            if state.count == 0 {
                Image(systemName: "checkmark")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(txt3)
            } else {
                Text("\(state.count)")
                    .font(.tc(15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(txt)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: capture（热键速记，一闪即收）
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            smallInputRow
            smallWindowListContent
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { if state.hasUndo { undoBar } }
        .overlay(alignment: .bottom) {
            if state.shouldShowUpdateBanner {
                updateNoticeBanner
                    .padding(.bottom, state.hasUndo ? 38 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottomLeading) { smallFooterTools }
    }

    private var header: some View {
        HStack(spacing: 8) {
            smallListMenu
            Text("\(smallCurrentCount)")
                .font(.tc(11.5, weight: .semibold))
                .foregroundStyle(txt2)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(txt2.opacity(0.16)))
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
        .padding(.horizontal, 4)
        .highPriorityGesture(TapGesture(count: 2).onEnded {
            withAnimation(anim) { state.enterPanel() }
        })
        .simultaneousGesture(smallWindowDragGesture)
    }

    var smallListMenu: some View {
        Menu {
            ForEach(state.lists) { list in
                Button {
                    withAnimation(anim) { state.selectList(list.id) }
                } label: {
                    smallMenuItem(
                        title: list.name,
                        systemImage: "list.bullet",
                        isSelected: state.panelTab == .today && state.selectedListId == list.id
                    )
                }
            }
            Divider()
            Button {
                withAnimation(anim) { state.setPanelTab(.collect) }
            } label: {
                smallMenuItem(
                    title: "收藏",
                    systemImage: "bookmark",
                    isSelected: state.panelTab == .collect
                )
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 8, height: 8)
                    .fontWeight(.semibold)
                    .foregroundStyle(txt2)
                Text(state.panelTab == .collect ? "收藏" : state.currentList.name)
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(txt)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(txt2)
        .fixedSize()
        .help("切换清单")
        .pointingHandCursor()
    }

    @ViewBuilder
    private func smallMenuItem(title: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? accent.opacity(0.13) : Color.clear)
        )
    }

    @ViewBuilder
    var summaryToast: some View {
        if state.mode != .idle, let message = state.summaryToast, !message.isEmpty {
            HStack(spacing: 10) {
                Text(message)
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(txt)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                if message.hasPrefix("生成完成"), let summaryID = state.latestGeneratedSummaryID {
                    Button("查看") {
                        workspaceDestination = .summary
                        selectedSummaryID = summaryID
                        withAnimation(anim) { state.enterPanel() }
                        state.onRequestKey?()
                    }
                    .buttonStyle(.plain)
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(accent)
                    .pointingHandCursor()
                }
            }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(usesLightTheme ? Color.white.opacity(0.96) : Color(hex: 0x2C2C30).opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(txt3.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(usesLightTheme ? 0.14 : 0.38), radius: 14, x: 0, y: 6)
                .padding(.horizontal, 18)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
                .zIndex(10)
        }
    }

    var smallMoreMenu: some View {
        Menu {
            Button { withAnimation(anim) { state.importClipboardToTodos() } } label: {
                Label("粘贴复制内容", systemImage: "doc.on.clipboard")
            }
            .disabled(state.lastClipboardText.isEmpty)
            Button { state.makeSummary() } label: {
                Label("AI总结", systemImage: "sparkles")
            }
            Divider()
            Button { state.openSettings() } label: {
                Label("设置", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.tc(13, weight: .bold))
                .foregroundStyle(txt2)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(txt2)
        .help("更多")
        .pointingHandCursor()
    }

    var smallWindowDragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { state.onPanelDragChanged?($0.translation) }
            .onEnded { _ in state.onPanelDragEnded?() }
    }

    private var captureInputActive: Bool {
        inputFocused || state.mode == .capture
    }

    var captureRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.tc(15))
                .foregroundStyle(captureInputActive ? accent : txt3)
            ZStack(alignment: .leading) {
                // 自绘灰色占位（macOS TextField 原生 placeholder 不跟 foregroundStyle → 深底变黑字）
                if state.draft.isEmpty {
                    Text("记一条…").font(.tc(13)).foregroundStyle(txt3)
                }
                TextField("", text: $state.draft)
                    .textFieldStyle(.plain)
                    .font(.tc(13))
                    .foregroundStyle(txt)
                    .tint(accent)
                    .focused($inputFocused)
                    .onSubmit { doSubmit() }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(captureInputActive ? accent.opacity(0.08) : subtleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(captureInputActive ? accent.opacity(0.6) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if state.mode != .panel { state.enterCapture() }
            inputFocused = true
            state.onRequestKey?()
        }  // 经 controller 抢 key，否则 nonactivating panel 上 TextField 收不到键盘
        .overlay(alignment: .topLeading) {
            let suggestions = tagSuggestions(in: state.draft)
            if !suggestions.isEmpty {
                TagSuggestionDropdown(tags: suggestions, usesLightTheme: usesLightTheme) { tag in
                    applyTagSuggestion(tag.name)
                }
                .offset(x: 24, y: 34)
                .zIndex(30)
            }
        }
        .zIndex(tagSuggestions(in: state.draft).isEmpty ? 0 : 30)
    }

    @ViewBuilder
    var smallInputRow: some View {
        if state.panelTab == .collect {
            collectInputRow
        } else {
            captureRow
        }
    }

    func tagSuggestions(in text: String) -> [TodoTag] {
        guard let query = tagQuery(in: text) else { return [] }
        return state.tags
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .prefix(5)
            .map { $0 }
    }

    private func tagQuery(in text: String) -> String? {
        guard let last = text.components(separatedBy: .whitespacesAndNewlines).last,
              last.hasPrefix("#") else { return nil }
        return TodoTag.normalize(last)
    }

    private func applyTagSuggestion(_ name: String) {
        var parts = state.draft.components(separatedBy: .whitespacesAndNewlines)
        if parts.last?.hasPrefix("#") == true {
            parts.removeLast()
        }
        parts.append("#\(name)")
        state.draft = parts.filter { !$0.isEmpty }.joined(separator: " ") + " "
        inputFocused = true
        state.onRequestKey?()
    }

    // 自绘行（不再用 List，彻底掌控点击命中）
    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 1) {
                ForEach(state.active) { todo in row(todo) }
            }
        }
    }

    @ViewBuilder
    var smallWindowListContent: some View {
        if state.panelTab == .collect {
            if state.collects.isEmpty {
                collectEmptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 1) {
                        ForEach(state.collects) { item in smallCollectRow(item) }
                    }
                }
            }
        } else if state.active.isEmpty {
            emptyState
        } else {
            list
        }
    }

    var smallCurrentCount: Int {
        state.panelTab == .collect ? state.collects.count : state.active.count
    }

    // MARK: 文本内 URL 识别 → 渲染为可点击链接（系统 NSDataDetector，点击用默认浏览器打开）
    static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    func linkedText(_ raw: String) -> AttributedString {
        var attr = AttributedString(raw)
        guard let detector = Self.linkDetector else { return attr }
        let matches = detector.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        for m in matches {
            guard let url = m.url, let strRange = Range(m.range, in: raw),
                  let attrRange = Range(strRange, in: attr) else { continue }
            attr[attrRange].link = url
            attr[attrRange].foregroundColor = accent
            attr[attrRange].underlineStyle = .single
        }
        return attr
    }

    func detectedLinks(in raw: String) -> [URL] {
        guard let detector = Self.linkDetector else { return [] }
        var seen = Set<String>()
        return detector.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)).compactMap { match in
            guard let url = match.url else { return nil }
            let key = url.absoluteString
            return seen.insert(key).inserted ? url : nil
        }
    }

    // 保留这个函数名，供面板和一瞥视图共用文本渲染。
    func taggedText(_ raw: String) -> some View {
        Text(linkedText(raw)).textSelection(.enabled)
    }

    private func row(_ todo: Todo) -> some View {
        let editing = editingId == todo.id
        let hovered = hoveredRow == todo.id || (Self.forceHover && todo.id == state.active.first?.id)
        return HStack(spacing: 10) {
            // 勾选框：整块 18×18 可点（contentShape 修掉"点不动"）
            Button {
                withAnimation(anim) { state.complete(todo) }
            } label: {
                Circle()
                    .strokeBorder(txt3, lineWidth: 1.6)
                    .frame(width: 18, height: 18)
                    .frame(width: 26, height: 26)    // 命中区放大
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("完成")
            .pointingHandCursor()

            if editing {
                editTextArea(todo)
            } else {
                taggedText(todo.text)
                    .font(.tc(13))
                    .foregroundStyle(txt)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if editing {
                editableTagPills(todo)
            } else {
                tagPills(todo.tags)
            }
            pinPill(todo)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 8).fill(editing ? accent.opacity(0.10) : (hovered ? Color.white.opacity(0.05) : Color.white.opacity(0.001))))
        .onHover { h in hoveredRow = h ? todo.id : (hoveredRow == todo.id ? nil : hoveredRow) }
        .highPriorityGesture(TapGesture(count: 2).onEnded { startEdit(todo) })
        .contextMenu { todoContextMenu(todo) }
        .zIndex(editing ? 30 : 0)
    }

    @ViewBuilder
    func pinPill(_ todo: Todo) -> some View {
        if todo.pinned {
            Button {
                withAnimation(anim) { state.togglePin(todo) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.tc(8, weight: .bold))
                    .foregroundStyle(txt3)
                    .frame(width: 10, height: 12)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(txt3.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .help("取消置顶")
            .pointingHandCursor()
        }
    }

    func editTextArea(_ todo: Todo) -> some View {
        TextField("", text: $editText)
            .textFieldStyle(.plain)
            .font(.tc(13))
            .foregroundStyle(txt)
            .tint(accent)
            .focused($editFocused)
            .onSubmit { commitEdit(todo) }
            .onChange(of: editFocused) { _, f in if !f { commitEdit(todo) } }
            .onExitCommand { cancelEdit() }
            .overlay(alignment: .topLeading) {
                let suggestions = tagSuggestions(in: editText).filter { !todo.tags.contains($0.name) }
                if !suggestions.isEmpty {
                    TagSuggestionDropdown(tags: suggestions, usesLightTheme: usesLightTheme) { tag in
                        applyEditTagSuggestion(tag.name)
                    }
                    .offset(y: 24)
                    .zIndex(30)
                }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyEditTagSuggestion(_ name: String) {
        var parts = editText.components(separatedBy: .whitespacesAndNewlines)
        if parts.last?.hasPrefix("#") == true {
            parts.removeLast()
        }
        parts.append("#\(name)")
        editText = parts.filter { !$0.isEmpty }.joined(separator: " ") + " "
        editFocused = true
        state.onRequestKey?()
    }

    func tagPills(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                tagPillLabel(tag, removable: false, color: tagColor(tag))
            }
        }
        .fixedSize()
    }

    func editableTagPills(_ todo: Todo) -> some View {
        HStack(spacing: 4) {
            ForEach(todo.tags, id: \.self) { tag in
                Button {
                    state.removeTagFromTodo(todo.id, tag: tag)
                } label: {
                    tagPillLabel(tag, removable: true, color: tagColor(tag))
                }
                .buttonStyle(.plain)
                .help("移除标签")
                .pointingHandCursor()
            }
        }
        .fixedSize()
    }

    func tagPillLabel(_ tag: String, removable: Bool, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("#\(tag)")
            if removable {
                Image(systemName: "xmark")
                    .font(.tc(8, weight: .bold))
            }
        }
        .font(.tc(10, weight: .semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.16)))
    }

    func tagColor(_ tag: String) -> Color {
        let palette: [UInt32] = [0x0B9153, 0x64D2FF, 0xBF8CFF, 0xFF9F0A, 0xFF5E7E, 0x5DE4C7]
        let sum = tag.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hex: palette[sum % palette.count])
    }

    @ViewBuilder
    func todoContextMenu(_ todo: Todo) -> some View {
        todoActionMenuItems(todo)
    }

    @ViewBuilder
    func todoActionMenuItems(_ todo: Todo) -> some View {
        Button {
            startEdit(todo)
        } label: {
            Label("编辑", systemImage: "pencil")
        }
        Button {
            withAnimation(anim) { state.togglePin(todo) }
        } label: {
            Label(todo.pinned ? "取消置顶" : "置顶", systemImage: todo.pinned ? "pin.slash" : "pin")
        }
        Menu {
            let targets = state.lists.filter { $0.id != todo.listId }
            if targets.isEmpty {
                Text("没有其他清单")
            } else {
                ForEach(targets) { list in
                    Button {
                        withAnimation(anim) { state.moveTodo(todo, to: list.id) }
                    } label: {
                        Label(list.name, systemImage: "tray.and.arrow.down")
                    }
                }
            }
        } label: {
            Label("转移", systemImage: "folder")
        }
        Button(role: .destructive) {
            withAnimation(anim) { state.deleteImmediately(todo) }
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().strokeBorder(accent, lineWidth: 2).frame(width: 32, height: 32)
                Image(systemName: "checkmark").font(.tc(14, weight: .bold)).foregroundStyle(accent)
            }
            Text("今日清零").font(.tc(13, weight: .semibold)).foregroundStyle(txt)
            Text("⌥Space 随手记一条").font(.tc(11.5)).foregroundStyle(txt3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 14)
    }

    var undoBar: some View {
        HStack(spacing: 8) {
            Text("\(state.undoVerb)「\(shortText)」").font(.tc(12)).foregroundStyle(txt2).lineLimit(1)
            Spacer()
            Button("撤回") { withAnimation(anim) { state.performUndo() } }
                .buttonStyle(.plain)
                .font(.tc(12, weight: .semibold))
                .foregroundStyle(accent)
                .pointingHandCursor()
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(usesLightTheme ? Color(hex: 0xF1F1F3) : Color(hex: 0x2C2C30)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(txt3.opacity(0.16)))
        .padding(6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var shortText: String {
        let t = state.undoItemText
        return t.count > 8 ? String(t.prefix(8)) + "…" : t
    }

    var smallFooterTools: some View {
        HStack(spacing: 8) {
            footerIcon("arrow.3.trianglepath", help: "查看已完成") {
                openCompletedWorkspace()
            }
            footerIcon("folder", help: "打开 Markdown 所在目录") {
                state.openMarkdownFolder()
            }
        }
        .padding(.leading, 18)
        .padding(.bottom, 12)
    }

    func openCompletedWorkspace() {
        state.showingArchive = false
        workspaceDestination = .completed
        withAnimation(anim) { state.enterPanel() }
        state.onRequestKey?()
    }

    func startEdit(_ todo: Todo) {
        state.isEditing = true
        editText = todo.text
        editingId = todo.id
        DispatchQueue.main.async { editFocused = true }
    }
    func commitEdit(_ todo: Todo) {
        guard editingId == todo.id else { return }
        state.updateText(todo.id, editText)
        editingId = nil
        state.isEditing = false
    }
    // Esc 取消行内编辑：先清 editingId —— 失焦触发的 commitEdit 会因 guard editingId==todo.id 失败而不写入（本次编辑丢弃）
    func cancelEdit() {
        editingId = nil
        state.isEditing = false
    }
    /// best-effort：输入法组字（marked text）中途不要展开，否则会打断拼音候选。取当前 field editor 探测；
    /// 取不到（如 nonactivating 面板 keyWindow 为 nil）则返回 false（不拦截，退化为原行为，绝不因此卡输入）。
    static func isIMEComposing() -> Bool {
        guard let tv = NSApplication.shared.keyWindow?.firstResponder as? NSTextView else { return false }
        return tv.hasMarkedText()
    }

    // 连续录入：回车 = 新行入列 + 清空 + 保持聚焦写下一条；退出用 Esc / 点外部
    private func doSubmit() {
        guard !state.draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(anim) { state.submit() }          // 新行 spring 入列(顶部)；submit 内清空 draft
        DispatchQueue.main.async { inputFocused = true } // 重新激活输入框，接着写
    }
}

struct TagSuggestionDropdown: View {
    let tags: [TodoTag]
    let usesLightTheme: Bool
    let onSelect: (TodoTag) -> Void
    @State private var hoveredTagID: String?

    private var background: Color {
        usesLightTheme ? Color.white : Color(hex: 0x3A3A3A)
    }

    private var rowHover: Color {
        usesLightTheme ? Color.black.opacity(0.10) : Color.white.opacity(0.10)
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(tags.prefix(5)) { tag in
                Button {
                    onSelect(tag)
                } label: {
                    Text(tag.name)
                        .font(.tc(13))
                        .foregroundStyle(usesLightTheme ? Color(hex: 0x1D1D1F) : Color.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(hoveredTagID == tag.id ? rowHover : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredTagID = hovering ? tag.id : (hoveredTagID == tag.id ? nil : hoveredTagID)
                }
                .pointingHandCursor()
            }
        }
        .padding(4)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(background))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(usesLightTheme ? Color.black.opacity(0.08) : Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(usesLightTheme ? 0.16 : 0.28), radius: 12, y: 5)
    }
}
