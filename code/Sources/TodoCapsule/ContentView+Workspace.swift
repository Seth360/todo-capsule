import SwiftUI
import AppKit

final class WorkspaceOverlayState: ObservableObject {
    @Published var showingSummaryMenu = false
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func installClickMonitor() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }
        // 在 mouseUp 后收起：事件仍会先完整交给菜单按钮，避免按下选项时浮层先消失、按钮收不到点击。
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
            guard let self else { return event }
            closeSummaryMenuAfterCurrentClick()
            return event
        }
        // 大窗是 nonactivating panel；点到可穿透区域时事件会归属底层 App，需同时监听全局事件。
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            self?.closeSummaryMenuAfterCurrentClick()
        }
    }

    private func closeSummaryMenuAfterCurrentClick() {
        guard showingSummaryMenu else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showingSummaryMenu = false
        }
    }

    func removeClickMonitor() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    deinit {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
    }
}

private enum WorkspaceOverlayAnchorID: Hashable {
    case summaryMenu
    case draftTags
    case todoTags(UUID)
}

private struct WorkspaceOverlayAnchorKey: PreferenceKey {
    static var defaultValue: [WorkspaceOverlayAnchorID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [WorkspaceOverlayAnchorID: Anchor<CGRect>],
                       nextValue: () -> [WorkspaceOverlayAnchorID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum WorkspaceDestination: Equatable {
    case all
    case summary
    case collect
    case list(String)
    case tag(String)
    case completed
    case trash
    case settings(SettingsSection)
}

enum WorkspaceDeletionTarget: Identifiable {
    case list(Checklist)
    case tag(TodoTag)

    var id: String {
        switch self {
        case .list(let list): return "list-\(list.id)"
        case .tag(let tag): return "tag-\(tag.id)"
        }
    }

    var title: String {
        switch self {
        case .list(let list): return "清单“\(list.name)”"
        case .tag(let tag): return "标签“\(tag.name)”"
        }
    }
}

extension ContentView {
    private var workspaceBackground: Color { usesLightTheme ? Color(hex: 0xF7F7F8) : Color(hex: 0x1C1C1C) }
    private var workspaceSidebarBackground: Color { usesLightTheme ? Color.white.opacity(0.68) : Color(hex: 0x191919) }
    private var workspaceInteractionFill: Color { usesLightTheme ? Color.black.opacity(0.10) : Color.white.opacity(0.10) }
    private var workspaceDivider: Color { workspaceInteractionFill }
    private var workspaceSelectedFill: Color { usesLightTheme ? Color.black.opacity(0.08) : Color.white.opacity(0.10) }
    private var workspaceMuted: Color { usesLightTheme ? Color.black.opacity(0.42) : Color.white.opacity(0.40) }
    private var workspaceRowHoverFill: Color { workspaceInteractionFill }
    private var workspaceRowHeight: CGFloat { 40 }
    private var workspaceTrailingWidth: CGFloat { 24 }
    private var workspaceAppIcon: NSImage {
        let sourceRootIcon = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
        return NSImage(contentsOf: sourceRootIcon) ?? NSApp.applicationIconImage
    }

    var largeWorkspace: some View {
        HStack(spacing: 0) {
            workspaceSidebar
                .fixedSize(horizontal: true, vertical: false)
            Rectangle().fill(workspaceDivider).frame(width: 1)
            workspaceContent
                .layoutPriority(1)
        }
        .background(workspaceBackground)
        .preferredColorScheme(preferredScheme)
        .overlayPreferenceValue(WorkspaceOverlayAnchorKey.self) { anchors in
            GeometryReader { proxy in
                workspaceOverlayLayer(anchors: anchors, proxy: proxy)
            }
        }
        .onChange(of: workspaceTodoEditFocused) { oldValue, newValue in
            guard let editedID = oldValue, newValue == nil else { return }
            DispatchQueue.main.async {
                if workspaceTodoEditFocused == nil, editingWorkspaceTodoID == editedID {
                    commitWorkspaceTodoEdit(editedID)
                }
            }
        }
        .onChange(of: workspaceDraftFocused) { oldValue, newValue in
            guard oldValue, !newValue else { return }
            DispatchQueue.main.async {
                if !workspaceDraftFocused {
                    workspaceTagSuggestionsDismissed = true
                }
            }
        }
        .onAppear { workspaceOverlayState.installClickMonitor() }
        .onDisappear { workspaceOverlayState.removeClickMonitor() }
    }

    @ViewBuilder
    private func workspaceOverlayLayer(
        anchors: [WorkspaceOverlayAnchorID: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        let draftSuggestions = workspaceTagSuggestionsDismissed ? [] : tagSuggestions(in: state.draft)
        let editSuggestions: [TodoTag] = if let id = editingWorkspaceTodoID,
                                           let todo = (workspaceActiveItems + workspaceCompletedItems).first(where: { $0.id == id }) {
            tagSuggestions(in: workspaceTodoEditText).filter { !todo.tags.contains($0.name) }
        } else {
            []
        }
        ZStack(alignment: .topLeading) {
            if workspaceOverlayState.showingSummaryMenu, let anchor = anchors[.summaryMenu] {
                let rect = proxy[anchor]
                let menuHeight = CGFloat(state.settings.summaryTemplates.count * 34 + 43)
                workspaceSummaryTemplateDropdown
                    .frame(width: 114)
                    .position(
                        x: min(max(rect.maxX - 57, 65), proxy.size.width - 65),
                        y: rect.maxY + 3 + menuHeight / 2
                    )
                    .zIndex(50)
            }

            if !draftSuggestions.isEmpty, let anchor = anchors[.draftTags] {
                let rect = proxy[anchor]
                let menuHeight = CGFloat(min(draftSuggestions.count, 5) * 34 + 8)
                TagSuggestionDropdown(tags: draftSuggestions, usesLightTheme: usesLightTheme) { tag in
                    workspaceApplyDraftTag(tag.name)
                }
                .position(
                    x: min(max(rect.minX + 110, 118), proxy.size.width - 118),
                    y: rect.maxY + 4 + menuHeight / 2
                )
                .zIndex(50)
            }

            if let id = editingWorkspaceTodoID,
               !editSuggestions.isEmpty,
               let anchor = anchors[.todoTags(id)] {
                let rect = proxy[anchor]
                let menuHeight = CGFloat(min(editSuggestions.count, 5) * 34 + 8)
                TagSuggestionDropdown(tags: editSuggestions, usesLightTheme: usesLightTheme) { tag in
                    workspaceApplyEditTag(tag.name)
                }
                .position(
                    x: min(max(rect.minX + 110, 118), proxy.size.width - 118),
                    y: rect.maxY + 4 + menuHeight / 2
                )
                .zIndex(50)
            }
        }
    }

    private var workspaceWindowControls: some View {
        HStack(spacing: 9) {
            workspaceWindowControl(color: Color(hex: 0xFF5F57), help: "关闭并收起到边缘") {
                state.closePanel()
            }
            workspaceWindowControl(color: Color(hex: 0xFEBC2E), help: "最小化到边缘") {
                state.closePanel()
            }
            workspaceWindowControl(color: Color(hex: 0x28C840), help: "缩放窗口") {
                state.zoomPanel()
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func workspaceWindowControl(color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle().fill(color).frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHandCursor()
    }

    private var workspaceSidebar: some View {
        VStack(spacing: 0) {
            workspaceWindowControls
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    workspaceNavRow(title: "所有待办项", icon: "tray.full", count: workspaceActiveItems.count,
                                    selected: workspaceDestination == .all) {
                        workspaceDestination = .all
                    }
                    workspaceNavRow(title: "智能总结", icon: "sparkles", count: nil,
                                    selected: workspaceDestination == .summary) {
                        workspaceDestination = .summary
                        selectedSummaryID = nil
                    }
                    workspaceNavRow(title: "我的收藏", icon: "bookmark", count: state.collects.count,
                                    selected: workspaceDestination == .collect) {
                        workspaceDestination = .collect
                    }
                    workspaceSeparator

                    VStack(spacing: 0) {
                        workspaceSectionHeader(title: "清单", action: {
                            creatingWorkspaceList = true
                        }, isHovered: $workspaceListSectionHovered, help: "新建清单")
                        ForEach(state.lists) { list in
                            workspaceListRow(list)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onHover { workspaceListSectionHovered = $0 }

                    workspaceSeparator

                    VStack(spacing: 0) {
                        workspaceSectionHeader(title: "标签", action: {
                            editingWorkspaceTag = TodoTag(id: "__new__", name: "")
                        }, isHovered: $workspaceTagHeaderHovered, help: "新建标签")
                        ForEach(state.tags) { tag in
                            workspaceTagRow(tag)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onHover { workspaceTagHeaderHovered = $0 }

                    workspaceSeparator
                    workspaceNavRow(title: "已完成", icon: "checkmark.circle", count: workspaceCompletedItems.count,
                                    selected: workspaceDestination == .completed) {
                        workspaceDestination = .completed
                    }
                    workspaceNavRow(title: "垃圾桶", icon: "trash", count: workspaceTrashItems.count,
                                    selected: workspaceDestination == .trash) {
                        workspaceDestination = .trash
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }

            if state.shouldShowUpdateBanner {
                workspaceUpdateNotice
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
            Rectangle().fill(workspaceDivider).frame(height: 1)
            Button { workspaceDestination = .settings(.general) } label: {
                HStack(spacing: 10) {
                    Image(nsImage: workspaceAppIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("Todo Capsule")
                        .font(.tc(13, weight: .semibold))
                        .foregroundStyle(txt)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.tc(10, weight: .semibold))
                        .foregroundStyle(txt3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .frame(width: 240)
        .background(workspaceSidebarBackground)
    }

    private var workspaceContent: some View {
        Group {
            switch workspaceDestination {
            case .summary:
                summaryWorkspace
            case .collect:
                workspaceCollectPage
            case .settings(let section):
                SettingsView(initialSection: section, embeddedInWorkspace: true)
                    .environmentObject(state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(workspaceBackground)
            case .all:
                workspaceListPage(title: "所有待办项", icon: "tray.full", active: workspaceActiveItems,
                                  completed: workspaceCompletedItems, inputListId: state.selectedListId)
            case .list(let id):
                let list = state.lists.first(where: { $0.id == id }) ?? state.currentList
                workspaceListPage(title: list.name, icon: "checklist", active: state.active(in: list.id),
                                  completed: workspaceCompletedItems.filter { $0.listId == list.id }, inputListId: list.id)
            case .tag(let name):
                workspaceTagPage(name: name)
            case .completed:
                workspaceCompletedPage
            case .trash:
                workspaceTrashPage
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(workspaceBackground)
    }

    private var workspaceUpdateNotice: some View {
        Button { state.openUpdateDialog() } label: {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("发现新版本")
                        .font(.tc(12, weight: .semibold))
                        .foregroundStyle(txt)
                    if let version = state.updateInfo?.version, !version.isEmpty {
                        Text("版本 \(version)")
                            .font(.tc(10, weight: .medium))
                            .foregroundStyle(txt3)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.tc(9, weight: .semibold))
                    .foregroundStyle(txt3)
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(accent.opacity(0.34)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func workspaceSectionHeader(title: String,
                                        action: (() -> Void)? = nil,
                                        isHovered: Binding<Bool> = .constant(false),
                                        help: String = "新建") -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.tc(11, weight: .semibold))
                .foregroundStyle(workspaceMuted)
            Spacer()
            if let action {
                Button(action: action) {
                    Image(systemName: "plus")
                        .font(.tc(11, weight: .semibold))
                        .frame(width: workspaceTrailingWidth, height: workspaceRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(txt2)
                .opacity(isHovered.wrappedValue ? 1 : 0)
                .help(help)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: workspaceRowHeight)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .contentShape(Rectangle())
    }

    private var workspaceSeparator: some View {
        Rectangle().fill(workspaceDivider).frame(height: 1).padding(.horizontal, 0).padding(.vertical, 10)
    }

    private func workspaceNavRow(title: String, icon: String, count: Int?, selected: Bool,
                                 tint: Color? = nil, action: @escaping () -> Void) -> some View {
        let hovered = hoveredWorkspaceNavTitle == title
        return Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.tc(13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(tint ?? (selected ? txt : txt2))
                    .frame(width: 18)
                Text(title)
                    .font(.tc(13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? txt : txt2)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.tc(11, weight: .medium))
                        .foregroundStyle(selected ? txt2 : workspaceMuted)
                        .monospacedDigit()
                        .frame(width: workspaceTrailingWidth, height: workspaceRowHeight, alignment: .center)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: workspaceRowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? workspaceSelectedFill : (hovered ? workspaceRowHoverFill : .clear)))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredWorkspaceNavTitle = $0 ? title : (hoveredWorkspaceNavTitle == title ? nil : hoveredWorkspaceNavTitle) }
        .pointingHandCursor()
    }

    private func workspaceListRow(_ list: Checklist) -> some View {
        let isSelected = workspaceDestination == .list(list.id)
        let isHovered = hoveredWorkspaceListID == list.id || Self.forceHover
        return Button {
                state.selectList(list.id)
                workspaceDestination = .list(list.id)
                activateWorkspaceDraft()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: list.pinned ? "pin.fill" : "checklist")
                    .font(.tc(13, weight: list.pinned ? .semibold : .regular))
                    .foregroundStyle(isSelected ? CapsuleDesign.primary : txt2)
                    .frame(width: 18)
                Text(list.name)
                    .font(.tc(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? txt : txt2)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(state.active(in: list.id).count)")
                    .font(.tc(11, weight: .medium))
                    .foregroundStyle(workspaceMuted)
                    .monospacedDigit()
                    .opacity(isHovered ? 0 : 1)
                    .frame(width: workspaceTrailingWidth, height: workspaceRowHeight, alignment: .center)
            }
            .padding(.horizontal, 12)
            .frame(height: workspaceRowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? workspaceSelectedFill : (isHovered ? workspaceRowHoverFill : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if isHovered {
                Menu {
                    Button(list.pinned ? "取消置顶" : "置顶") { state.toggleListPinned(id: list.id) }
                    Button("编辑") { editingWorkspaceList = list }
                    Divider()
                    Button("删除", role: .destructive) {
                        if state.listHasTodos(id: list.id) {
                            pendingWorkspaceDeletion = .list(list)
                        } else {
                            state.deleteList(id: list.id)
                            workspaceDestination = .list(state.selectedListId)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.tc(11, weight: .semibold))
                        .frame(width: workspaceTrailingWidth, height: workspaceRowHeight)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .foregroundStyle(txt3)
                .padding(.trailing, 12)
            }
        }
        .onHover { hoveredWorkspaceListID = $0 ? list.id : (hoveredWorkspaceListID == list.id ? nil : hoveredWorkspaceListID) }
        .pointingHandCursor()
    }

    private func workspaceTagRow(_ tag: TodoTag) -> some View {
        let isSelected = workspaceDestination == .tag(tag.name)
        let isHovered = hoveredWorkspaceTagID == tag.id || Self.forceHover
        return Button {
                workspaceDestination = .tag(tag.name)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: tag.pinned ? "pin.fill" : "tag")
                    .font(.tc(12, weight: tag.pinned ? .semibold : .regular))
                    .foregroundStyle(isSelected ? CapsuleDesign.primary : txt2)
                    .frame(width: 18)
                Text(tag.name)
                    .font(.tc(13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? txt : txt2)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(workspaceTagItems(tag.name).count)")
                    .font(.tc(11, weight: .medium))
                    .foregroundStyle(workspaceMuted)
                    .monospacedDigit()
                    .opacity(isHovered ? 0 : 1)
                    .frame(width: workspaceTrailingWidth, height: workspaceRowHeight, alignment: .center)
            }
            .padding(.horizontal, 12)
            .frame(height: workspaceRowHeight)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? workspaceSelectedFill : (isHovered ? workspaceRowHoverFill : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            if isHovered {
                Menu {
                    Button("编辑") { editingWorkspaceTag = tag }
                    Button(tag.pinned ? "取消置顶" : "置顶") { state.toggleTagPinned(id: tag.id) }
                    Button("合并到…") { mergingTag = tag }
                    Divider()
                    Button("删除", role: .destructive) { pendingWorkspaceDeletion = .tag(tag) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.tc(11, weight: .semibold))
                        .frame(width: workspaceTrailingWidth, height: workspaceRowHeight)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .foregroundStyle(txt3)
                .padding(.trailing, 12)
            }
        }
        .onHover { hoveredWorkspaceTagID = $0 ? tag.id : (hoveredWorkspaceTagID == tag.id ? nil : hoveredWorkspaceTagID) }
        .pointingHandCursor()
    }

    private var workspaceActiveItems: [Todo] {
        state.todos.filter { !$0.done && !$0.trashed }
    }

    private var workspaceCompletedItems: [Todo] { state.completedItems() }
    private var workspaceTrashItems: [Todo] { state.trashedItems() }

    private func workspaceTagItems(_ name: String) -> [Todo] {
        (workspaceActiveItems + workspaceCompletedItems).filter { $0.tags.contains(name) }
    }

    private func workspaceListPage(title: String, icon: String, active: [Todo], completed: [Todo],
                                   inputListId: String, showsInput: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            workspacePageHeader(title: title, icon: icon, showsSummaryAction: showsInput)
            if showsInput {
                workspaceCaptureBar(listId: inputListId)
                .padding(.horizontal, 28)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    workspaceTodoGroup(title: "进行中", todos: active, emptyText: "暂无进行中的待办")
                    workspaceTodoGroup(
                        title: "本周已完成",
                        todos: workspaceCurrentWeekCompleted(completed),
                        emptyText: "本周暂无已完成的待办",
                        actionTitle: "查看全部"
                    ) {
                        workspaceDestination = .completed
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 34)
            }
            .onTapGesture {
                if editingWorkspaceTodoID != nil {
                    cancelWorkspaceTodoEdit()
                }
            }
        }
    }

    private func workspacePageHeader(title: String, icon: String, showsSummaryAction: Bool = false) -> some View {
        return HStack(spacing: 10) {
            Image(systemName: icon).font(.tc(17, weight: .semibold)).foregroundStyle(txt2)
            Text(title).font(.tc(16, weight: .medium)).foregroundStyle(txt)
            Spacer()
            if showsSummaryAction {
                workspaceSummaryAction
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .zIndex(showsSummaryAction ? 30 : 0)
    }

    private var workspaceSummaryAction: some View {
        let controlWidth: CGFloat = 114
        return HStack(spacing: 0) {
            Button { state.makeSummary() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.tc(11, weight: .semibold))
                    Text("生成总结")
                        .font(.tc(12, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("使用当前模板生成总结")
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 28)
            Button {
                let shouldOpen = !workspaceOverlayState.showingSummaryMenu
                if shouldOpen {
                    DispatchQueue.main.async { workspaceOverlayState.showingSummaryMenu = true }
                } else {
                    workspaceOverlayState.showingSummaryMenu = false
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.tc(10, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("切换总结模板")
        }
        .frame(width: controlWidth, height: 28)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .anchorPreference(key: WorkspaceOverlayAnchorKey.self, value: .bounds) { [.summaryMenu: $0] }
        .zIndex(workspaceOverlayState.showingSummaryMenu ? 40 : 0)
        .pointingHandCursor()
    }

    private var workspaceSummaryTemplateDropdown: some View {
        VStack(spacing: 0) {
            ForEach(state.settings.summaryTemplates) { template in
                Button {
                    state.updateSummaryTemplate(template.id)
                    workspaceOverlayState.showingSummaryMenu = false
                } label: {
                    HStack(spacing: 8) {
                        Text(template.title)
                            .font(.tc(13))
                            .foregroundStyle(txt)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if template.id == state.settings.activeSummaryTemplateId {
                            Image(systemName: "checkmark")
                                .font(.tc(10, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        Rectangle().fill(
                            template.id == state.settings.activeSummaryTemplateId
                                ? workspaceSelectedFill
                                : (hoveredSummaryTemplateMenuID == template.id ? workspaceRowHoverFill : .clear)
                        )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredSummaryTemplateMenuID = hovering ? template.id : (hoveredSummaryTemplateMenuID == template.id ? nil : hoveredSummaryTemplateMenuID)
                }
                .pointingHandCursor()
            }
            Rectangle().fill(workspaceDivider).frame(height: 1)
            Button {
                workspaceOverlayState.showingSummaryMenu = false
                workspaceDestination = .settings(.summary)
            } label: {
                HStack(spacing: 8) {
                    Text("查看模板").font(.tc(13)).foregroundStyle(txt)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.tc(10, weight: .semibold))
                        .foregroundStyle(txt2)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(Rectangle().fill(hoveredSummaryTemplateMenuID == "__view_templates__" ? workspaceRowHoverFill : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredSummaryTemplateMenuID = hovering ? "__view_templates__" : (hoveredSummaryTemplateMenuID == "__view_templates__" ? nil : hoveredSummaryTemplateMenuID)
            }
            .pointingHandCursor()
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(usesLightTheme ? Color.white : Color(hex: 0x3A3A3A))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(workspaceDivider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: Color.black.opacity(usesLightTheme ? 0.14 : 0.30), radius: 10, y: 5)
    }

    private func workspaceCaptureBar(listId: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus").font(.tc(13, weight: .semibold)).foregroundStyle(txt3)
            TextField("记录一条待办，可输入 # 添加标签…", text: $state.draft)
                .textFieldStyle(.plain)
                .font(.tc(14))
                .foregroundStyle(txt)
                .focused($workspaceDraftFocused)
                .onSubmit {
                    state.addTodoLines(state.draft, listId: listId)
                    state.draft = ""
                }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(workspaceDraftFocused ? accent.opacity(0.08) : (usesLightTheme ? Color.black.opacity(0.055) : Color.white.opacity(0.07))))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(workspaceDraftFocused ? accent.opacity(0.6) : workspaceDivider, lineWidth: 1))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            workspaceDraftFocused = true
            state.onRequestKey?()
        }
        .anchorPreference(key: WorkspaceOverlayAnchorKey.self, value: .bounds) { [.draftTags: $0] }
        .onChange(of: state.draft) { _, _ in workspaceTagSuggestionsDismissed = false }
    }

    private func workspaceApplyDraftTag(_ name: String) {
        var parts = state.draft.components(separatedBy: .whitespacesAndNewlines)
        if parts.last?.hasPrefix("#") == true { parts.removeLast() }
        parts.append("#\(name)")
        state.draft = parts.filter { !$0.isEmpty }.joined(separator: " ") + " "
        workspaceDraftFocused = true
        state.onRequestKey?()
    }

    @ViewBuilder
    private func workspaceTodoGroup(title: String, todos: [Todo], emptyText: String,
                                    actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title).font(.tc(13, weight: .semibold)).foregroundStyle(txt)
                Text("\(todos.count)").font(.tc(11, weight: .medium)).foregroundStyle(txt3).monospacedDigit()
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.plain)
                        .font(.custom("Source Han Sans CN", size: 13).weight(.regular))
                        .foregroundStyle(Color(hex: 0x91959E))
                        .frame(height: 18)
                        .pointingHandCursor()
                }
            }
            if todos.isEmpty {
                Text(emptyText).font(.tc(12)).foregroundStyle(txt3).padding(.vertical, 8)
            } else {
                ForEach(todos) { workspaceTodoRow($0) }
            }
        }
    }

    private func workspaceCurrentWeekCompleted(_ todos: [Todo]) -> [Todo] {
        let interval = ArchiveDateGrouper.currentWeekInterval
        return todos.filter { interval.contains($0.completedAt ?? $0.createdAt) }
    }

    private func workspaceTodoRow(_ todo: Todo) -> some View {
        let hovered = hoveredWorkspaceTodoID == todo.id || Self.forceHover
        let editing = editingWorkspaceTodoID == todo.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    if todo.done { state.restoreCompleted(todo) } else { state.complete(todo) }
                } label: {
                    Image(systemName: todo.done ? "checkmark.square.fill" : "square")
                        .font(.tc(16, weight: .regular))
                        .foregroundStyle(todo.done ? accent : txt3)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                if editing {
                    TextField("待办内容，可输入 # 添加标签", text: $workspaceTodoEditText)
                        .textFieldStyle(.plain)
                        .font(.tc(14))
                        .foregroundStyle(txt)
                        .focused($workspaceTodoEditFocused, equals: todo.id)
                        .onSubmit { commitWorkspaceTodoEdit(todo.id) }
                        .onExitCommand { cancelWorkspaceTodoEdit() }
                        .anchorPreference(key: WorkspaceOverlayAnchorKey.self, value: .bounds) { [.todoTags(todo.id): $0] }
                } else {
                    Text(todo.text)
                        .font(.tc(14))
                        .foregroundStyle(todo.done ? txt3 : txt)
                        .strikethrough(todo.done, color: txt3)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if editing {
                    editableTagPills(todo)
                } else {
                    tagPills(todo.tags)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .frame(minHeight: workspaceRowHeight)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(editing ? accent.opacity(0.10) : (hovered ? workspaceRowHoverFill : .clear)))
        .overlay(alignment: .bottom) { Rectangle().fill(workspaceDivider).frame(height: 1).padding(.leading, 40) }
        .contentShape(Rectangle())
        .onHover { hoveredWorkspaceTodoID = $0 ? todo.id : (hoveredWorkspaceTodoID == todo.id ? nil : hoveredWorkspaceTodoID) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { startWorkspaceTodoEdit(todo) })
        .contextMenu {
            Button(todo.pinned ? "取消置顶" : "置顶") { state.togglePin(todo) }
            Button("加到收藏") { state.moveToCollect(todo) }
            Divider()
            Button("删除", role: .destructive) { state.delete(todo) }
        }
        .pointingHandCursor()
        .zIndex(editing ? 30 : 0)
    }

    private func workspaceApplyEditTag(_ name: String) {
        var parts = workspaceTodoEditText.components(separatedBy: .whitespacesAndNewlines)
        if parts.last?.hasPrefix("#") == true { parts.removeLast() }
        parts.append("#\(name)")
        workspaceTodoEditText = parts.filter { !$0.isEmpty }.joined(separator: " ") + " "
        workspaceTodoEditFocused = editingWorkspaceTodoID
        state.onRequestKey?()
    }

    private func activateWorkspaceDraft() {
        state.onRequestKey?()
        DispatchQueue.main.async { workspaceDraftFocused = true }
    }

    private func startWorkspaceTodoEdit(_ todo: Todo) {
        editingWorkspaceTodoID = todo.id
        workspaceTodoEditText = todo.text
        state.isEditing = true
        DispatchQueue.main.async { workspaceTodoEditFocused = todo.id }
    }

    private func commitWorkspaceTodoEdit(_ id: UUID) {
        guard editingWorkspaceTodoID == id else { return }
        state.updateText(id, workspaceTodoEditText)
        editingWorkspaceTodoID = nil
        workspaceTodoEditFocused = nil
        state.isEditing = false
    }

    private func cancelWorkspaceTodoEdit() {
        editingWorkspaceTodoID = nil
        workspaceTodoEditFocused = nil
        state.isEditing = false
    }

    private var summaryWorkspace: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.tc(17, weight: .semibold)).foregroundStyle(CapsuleDesign.primary)
                    Text("智能总结").font(.tc(16, weight: .medium)).foregroundStyle(txt)
                    Spacer()
                    workspaceSummaryAction
                }
                .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 18)
                Rectangle().fill(workspaceDivider).frame(height: 1)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(state.summaries) { summary in
                            Button {
                                selectedSummaryID = summary.id
                            } label: {
                                Text(summaryListTitle(summary))
                                    .font(.tc(13, weight: selectedSummaryID == summary.id ? .semibold : .regular))
                                    .foregroundStyle(selectedSummaryID == summary.id ? txt : txt2)
                                    .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .frame(height: workspaceRowHeight)
                                .background(RoundedRectangle(cornerRadius: 8).fill(selectedSummaryID == summary.id ? workspaceSelectedFill : (hoveredWorkspaceSummaryID == summary.id ? workspaceRowHoverFill : .clear)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .bottom) { Rectangle().fill(workspaceDivider).frame(height: 1) }
                            .onHover { hoveredWorkspaceSummaryID = $0 ? summary.id : (hoveredWorkspaceSummaryID == summary.id ? nil : hoveredWorkspaceSummaryID) }
                            .contentShape(Rectangle())
                            .pointingHandCursor()
                        }
                        if state.summaries.isEmpty {
                            Text("还没有总结记录")
                                .font(.tc(12)).foregroundStyle(txt3).padding(12)
                        }
                    }
                    .padding(10)
                }
            }
            .frame(width: selectedSummaryID == nil ? nil : 280)
            .frame(maxWidth: selectedSummaryID == nil ? .infinity : nil)
            if let id = selectedSummaryID, let summary = state.summaries.first(where: { $0.id == id }) {
                Rectangle().fill(workspaceDivider).frame(width: 1)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(summaryTitle(summary)).font(.tc(16, weight: .medium)).foregroundStyle(txt)
                            Spacer()
                            Button { selectedSummaryID = nil } label: {
                                Image(systemName: "xmark").font(.tc(12, weight: .semibold)).foregroundStyle(txt3)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(summary.createdAt, style: .date).font(.tc(11)).foregroundStyle(txt3)
                        Text(summary.text)
                            .font(.tc(14))
                            .foregroundStyle(txt)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: selectedSummaryID)
    }

    private func summaryTitle(_ summary: SummaryRecord) -> String {
        let first = summary.text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "") }
            .first(where: { !$0.isEmpty }) ?? "智能总结"
        return String(first.prefix(34))
    }

    private func summaryListTitle(_ summary: SummaryRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return "\(formatter.string(from: summary.createdAt)) 本周总结"
    }

    private func workspaceTagPage(name: String) -> some View {
        let active = workspaceActiveItems.filter { $0.tags.contains(name) }
        let completed = workspaceCompletedItems.filter { $0.tags.contains(name) }
        return workspaceListPage(title: "#\(name)", icon: "tag", active: active, completed: completed, inputListId: state.selectedListId)
    }

    private var workspaceCollectPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspacePageHeader(title: "我的收藏", icon: "bookmark")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if state.collects.isEmpty {
                        Text("还没有收藏内容")
                            .font(.tc(13))
                            .foregroundStyle(txt3)
                            .padding(.top, 18)
                    } else {
                        ForEach(state.collects) { item in
                            collectRow(item)
                            .frame(minHeight: workspaceRowHeight)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(workspaceDivider).frame(height: 1).padding(.leading, 22)
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
            }
        }
    }

    private var workspaceCompletedPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspacePageHeader(title: "全部已完成", icon: "checkmark.circle")
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.tc(12, weight: .semibold))
                        .foregroundStyle(txt3)
                    TextField("搜索完成项", text: $workspaceCompletedSearch)
                        .textFieldStyle(.plain)
                        .font(.tc(13))
                        .foregroundStyle(txt)
                }
                .padding(.horizontal, 11)
                .frame(width: 220, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(usesLightTheme ? Color.black.opacity(0.055) : Color.white.opacity(0.07)))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        workspaceCompletedFilter(title: "全部", selected: workspaceCompletedTag == nil) {
                            workspaceCompletedTag = nil
                        }
                        ForEach(workspaceCompletedTags, id: \.self) { tag in
                            workspaceCompletedFilter(title: tag, selected: workspaceCompletedTag == tag) {
                                workspaceCompletedTag = tag
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 18)

            Rectangle().fill(workspaceDivider).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if workspaceFilteredCompleted.isEmpty {
                        Text("没有匹配的完成项")
                            .font(.tc(13))
                            .foregroundStyle(txt3)
                            .padding(.top, 18)
                    } else {
                        ForEach(workspaceCompletedDayGroups, id: \.date) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(workspaceCompletedDateTitle(group.date))
                                    .font(.tc(12, weight: .semibold))
                                    .foregroundStyle(txt3)
                                ForEach(group.items) { item in
                                    workspaceCompletedRow(item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    private func workspaceCompletedFilter(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(selected ? title : "#\(title)")
                .font(.tc(11, weight: .semibold))
                .foregroundStyle(selected ? accent : txt2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill((selected ? accent : txt3).opacity(selected ? 0.18 : 0.12)))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func workspaceCompletedRow(_ todo: Todo) -> some View {
        let hovered = hoveredWorkspaceCompletedID == todo.id
        return HStack(spacing: 12) {
            Button { state.restoreCompleted(todo) } label: {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.tc(15, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("恢复到待办")
            .pointingHandCursor()
            VStack(alignment: .leading, spacing: 4) {
                Text(todo.text)
                    .font(.tc(14, weight: .medium))
                    .foregroundStyle(txt)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    Text(workspaceCompletedTime(todo.completedAt ?? todo.createdAt))
                        .font(.tc(11))
                        .foregroundStyle(txt3)
                    tagPills(todo.tags)
                }
            }
            Spacer(minLength: 8)
            Button { state.moveCompletedToTrash(todo) } label: {
                Image(systemName: "trash")
                    .font(.tc(12, weight: .semibold))
                    .foregroundStyle(txt3)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0)
            .help("移到垃圾桶")
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? workspaceRowHoverFill : (usesLightTheme ? Color.black.opacity(0.045) : Color.white.opacity(0.07))))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(workspaceDivider))
        .contentShape(Rectangle())
        .onHover { hoveredWorkspaceCompletedID = $0 ? todo.id : (hoveredWorkspaceCompletedID == todo.id ? nil : hoveredWorkspaceCompletedID) }
    }

    private var workspaceCompletedTags: [String] {
        Array(Set(workspaceCompletedItems.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var workspaceFilteredCompleted: [Todo] {
        let query = workspaceCompletedSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        return workspaceCompletedItems.filter { item in
            let matchesText = query.isEmpty || item.text.localizedCaseInsensitiveContains(query)
            let matchesTag = workspaceCompletedTag.map { item.tags.contains($0) } ?? true
            return matchesText && matchesTag
        }
    }

    private var workspaceCompletedDayGroups: [(date: Date, items: [Todo])] {
        let grouped = Dictionary(grouping: workspaceFilteredCompleted) {
            Calendar.current.startOfDay(for: $0.completedAt ?? $0.createdAt)
        }
        return grouped.map { (date: $0.key, items: $0.value) }.sorted { $0.date > $1.date }
    }

    private func workspaceCompletedDateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func workspaceCompletedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private var workspaceTrashPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspacePageHeader(title: "垃圾桶", icon: "trash")
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if workspaceTrashItems.isEmpty {
                        Text("垃圾桶为空").font(.tc(13)).foregroundStyle(txt3).padding(.top, 18)
                    } else {
                        ForEach(workspaceTrashItems) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "trash").foregroundStyle(txt3).frame(width: 22)
                                Text(item.text).font(.tc(14)).foregroundStyle(txt2).lineLimit(2)
                                Spacer()
                                Button { state.restoreFromArchive(item) } label: {
                                    Text("恢复").font(.tc(12, weight: .semibold)).foregroundStyle(accent)
                                }.buttonStyle(.plain).pointingHandCursor()
                                Button { state.deleteFromArchive(item) } label: {
                                    Image(systemName: "xmark").font(.tc(11, weight: .semibold)).foregroundStyle(txt3)
                                        .frame(width: 24, height: 24)
                                }.buttonStyle(.plain).pointingHandCursor()
                            }
                            .padding(.horizontal, 9).frame(minHeight: 42)
                            .background(RoundedRectangle(cornerRadius: 8).fill(usesLightTheme ? Color.black.opacity(0.025) : Color.white.opacity(0.025)))
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.top, 18)
            }
        }
    }
}

struct MergeTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let source: TodoTag
    let tags: [TodoTag]
    let onMerge: (String) -> Void
    @State private var targetName: String

    init(source: TodoTag, tags: [TodoTag], onMerge: @escaping (String) -> Void) {
        self.source = source
        self.tags = tags
        self.onMerge = onMerge
        _targetName = State(initialValue: tags.first(where: { $0.id != source.id })?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CapsuleDesign.Space.sm) {
            HStack {
                Text("合并标签到…").font(.tc(20, weight: .semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
            }
            Text("你可以将标签“\(source.name)”下的任务合并到另一个标签。合并后，源标签将被删除。")
                .font(.tc(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Menu {
                ForEach(tags.filter { $0.id != source.id }) { tag in
                    Button(tag.name) { targetName = tag.name }
                }
            } label: { CapsuleDropdownLabel(title: targetName.isEmpty ? "选择标签" : targetName, minWidth: 170) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(CapsuleSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("确认") { onMerge(targetName); dismiss() }
                    .buttonStyle(CapsulePrimaryButtonStyle())
                    .disabled(targetName.isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 500)
    }
}

struct TagEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: String
    let onSave: (String) -> Void
    @State private var value: String

    init(initial: String, onSave: @escaping (String) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CapsuleDesign.Space.md) {
            Text(initial.isEmpty ? "新建标签" : "编辑标签").font(.tc(19, weight: .semibold))
            TextField("标签名称", text: $value)
                .textFieldStyle(.plain)
                .font(.tc(14))
                .padding(.horizontal, CapsuleDesign.Space.sm)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: CapsuleDesign.Radius.field).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: CapsuleDesign.Radius.field).strokeBorder(CapsuleDesign.borderDark, lineWidth: 1))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(CapsuleSecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存") { onSave(value); dismiss() }
                    .buttonStyle(CapsulePrimaryButtonStyle())
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 380)
    }
}

struct ListEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let initial: String
    let onSave: (String) -> Void
    @State private var value: String

    init(initial: String, onSave: @escaping (String) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _value = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CapsuleDesign.Space.md) {
            Text(initial.isEmpty ? "新建清单" : "编辑清单").font(.tc(19, weight: .semibold))
            TextField("清单名称", text: $value)
                .textFieldStyle(.plain)
                .font(.tc(14))
                .padding(.horizontal, CapsuleDesign.Space.sm)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: CapsuleDesign.Radius.field).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: CapsuleDesign.Radius.field).strokeBorder(CapsuleDesign.borderDark, lineWidth: 1))
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(CapsuleSecondaryButtonStyle())
                Button("保存") { onSave(value); dismiss() }
                    .buttonStyle(CapsulePrimaryButtonStyle())
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 380)
    }
}
