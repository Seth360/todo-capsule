import AppKit
import ServiceManagement
import SwiftUI

/// 胶囊形态。idle/peek/capture = 小胶囊三态；panel = 主动打开的持久大面板。
enum CapsuleMode { case idle, peek, capture, panel }

/// 大面板主内容：清单与收藏是并行空间；清单内部再由 selectedListId 切换目录。
enum PanelTab { case today, collect }

enum AppUpdatePhase: Equatable {
    case available
    case downloading
    case readyToRestart
    case installing
    case checking
    case upToDate
    case error
}

struct AppUpdateInfo: Equatable {
    var version: String
    var title: String
    var notes: String
    var phase: AppUpdatePhase
    var progress: Double
    var statusText: String
}

private let undoWindow: TimeInterval = 4
private let windowPinnedKey = "todoCapsule.windowPinned.v1"

final class AppState: ObservableObject {
    @Published var mode: CapsuleMode = .idle
    @Published var todos: [Todo] = []
    @Published var completedArchive: [Todo] = []
    @Published var lists: [Checklist] = []
    @Published var tags: [TodoTag] = []
    @Published var selectedListId: String = defaultChecklistId
    @Published var draft: String = ""
    @Published var isEditing: Bool = false
    @Published var collects: [CollectItem] = []
    @Published var panelTab: PanelTab = .today
    @Published var collectDraft: String = ""
    @Published var lastClipboardText: String = ""
    @Published var windowPinned: Bool = false
    @Published var summaryStatus: String?
    @Published var summaryToast: String?
    @Published var showingArchive: Bool = false
    @Published var summaries: [SummaryRecord] = []
    @Published var latestGeneratedSummaryID: UUID?
    @Published var updateInfo: AppUpdateInfo?
    @Published var dismissedUpdateBannerVersion: String?
    @Published var presetQuota: PresetQuota?
    @Published var presetQuotaStatus: String?
    @Published var isPresetActivated: Bool = PresetActivation.isActivated
    @Published var settings: AppSettings = AppSettingsStore.load() {
        didSet {
            AppSettingsStore.save(settings)
            applyLaunchAtLogin()
            persistAll()
            relayout()
            onSettingsChanged?()
        }
    }
    @Published private var undoVersion = 0

    private enum UndoKind { case completed, deleted, collectDeleted }
    private struct Pending {
        let kind: UndoKind
        let item: Todo?
        let collectItem: CollectItem?
        let afterId: UUID?
        let collectIndex: Int?
        let work: DispatchWorkItem
    }
    private var pending: [UUID: Pending] = [:]
    private var pendingOrder: [UUID] = []
    private var summaryToastWork: DispatchWorkItem?

    var onLayout: ((CapsuleMode) -> Void)?
    var onPanelDragChanged: ((CGSize) -> Void)?
    var onPanelDragEnded: (() -> Void)?
    var onRequestKey: (() -> Void)?
    var onZoomPanel: (() -> Void)?
    var onPinnedChanged: ((Bool) -> Void)?
    var onSettingsChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenUpdateDialog: (() -> Void)?
    var onCheckForUpdates: (() -> Void)?
    var onInstallUpdate: (() -> Void)?
    var onDismissUpdate: (() -> Void)?
    var onSkipUpdate: (() -> Void)?
    var onRestartForUpdate: (() -> Void)?

    init() {
        lists = ChecklistStore.load()
        selectedListId = lists.first?.id ?? defaultChecklistId
        todos = TodoStore.load().map { item in
            var copy = item
            if !lists.contains(where: { $0.id == copy.listId }) { copy.listId = selectedListId }
            return copy
        }.filter { !$0.done && !$0.trashed }
        completedArchive = CompletedTodoStore.load()
        tags = TagStore.load()
        syncTagsFromTodos()
        collects = CollectStore.load()
        summaries = SummaryRecordStore.load()
        settings.summonHotkeyIndex = normalizedIndex(settings.summonHotkeyIndex, count: Settings.hotkeyOptions.count)
        settings.quickRecordHotkeyIndex = normalizedIndex(settings.quickRecordHotkeyIndex, count: Settings.quickRecordHotkeyOptions.count)
        settings.normalize()
        windowPinned = UserDefaults.standard.bool(forKey: windowPinnedKey)
        applyLaunchAtLogin()
        persistAll()
    }

    var currentList: Checklist {
        lists.first(where: { $0.id == selectedListId }) ?? .todo
    }

    var active: [Todo] {
        active(in: selectedListId)
    }

    func active(in listId: String) -> [Todo] {
        todos.filter { !$0.done && !$0.trashed && $0.listId == listId }
            .enumerated()
            .sorted { l, r in
                if l.element.pinned != r.element.pinned { return l.element.pinned }
                return l.offset < r.offset
            }
            .map { $0.element }
    }

    var completed: [Todo] {
        todos.filter { $0.done && !$0.trashed && $0.listId == selectedListId }
            .sorted { a, b in
                let ca = a.completedAt ?? .distantPast, cb = b.completedAt ?? .distantPast
                if ca != cb { return ca > cb }
                return a.id.uuidString < b.id.uuidString
            }
    }

    var count: Int {
        todos.filter { !$0.done && !$0.trashed }.count
    }

    var hasUndo: Bool { _ = undoVersion; return pendingOrder.last.flatMap { pending[$0] } != nil }
    var undoItem: Todo? { _ = undoVersion; return pendingOrder.last.flatMap { pending[$0]?.item } }
    var undoItemText: String {
        guard let id = pendingOrder.last, let p = pending[id] else { return "" }
        return p.item?.text ?? p.collectItem?.text ?? ""
    }
    var undoVerb: String {
        guard let id = pendingOrder.last, let p = pending[id] else { return "已完成" }
        return p.kind == .completed ? "已完成" : "已删除"
    }

    var shouldShowUpdateBanner: Bool {
        guard let info = updateInfo else { return false }
        guard dismissedUpdateBannerVersion != info.version else { return false }
        return info.phase == .available || info.phase == .downloading || info.phase == .readyToRestart
    }

    var shouldShowSettingsUpdateNotice: Bool {
        guard let phase = updateInfo?.phase else { return false }
        return phase != .upToDate && phase != .error
    }

    func relayout() { onLayout?(mode) }

    func setMode(_ m: CapsuleMode) {
        mode = m
        if m == .idle { isEditing = false }
        relayout()
    }

    func enterPeek() { if mode == .idle { setMode(.peek) } }
    func enterCapture() { setMode(.capture) }
    func enterPanel() { setMode(.panel) }
    func closePanel() {
        setMode(.idle)
    }
    func zoomPanel() { onZoomPanel?() }
    func collapseFromPeek() { guard mode == .peek else { return }; setMode(.idle) }
    func openSettings() { onOpenSettings?() }
    func openUpdateDialog() { onOpenUpdateDialog?() }
    func checkForUpdates() { onCheckForUpdates?() }
    func installUpdate() { onInstallUpdate?() }
    func dismissUpdate() { onDismissUpdate?() }
    func skipUpdate() { onSkipUpdate?() }
    func restartForUpdate() { onRestartForUpdate?() }

    func dismissUpdateBanner() {
        dismissedUpdateBannerVersion = updateInfo?.version
    }

    func setUpdateAvailable(version: String, title: String, notes: String) {
        updateInfo = AppUpdateInfo(
            version: version,
            title: title.isEmpty ? "Todo Capsule \(version)" : title,
            notes: notes.isEmpty ? "这个版本包含改进和修复。" : notes,
            phase: .available,
            progress: 0,
            statusText: "发现新版本 \(version)"
        )
        dismissedUpdateBannerVersion = nil
        relayout()
    }

    func setUpdateChecking() {
        if updateInfo == nil {
            updateInfo = AppUpdateInfo(
                version: "",
                title: "正在检查更新",
                notes: "",
                phase: .checking,
                progress: 0,
                statusText: "正在检查更新..."
            )
        } else {
            updateInfo?.phase = .checking
            updateInfo?.statusText = "正在检查更新..."
        }
    }

    func setUpdateDownloadProgress(_ progress: Double) {
        guard updateInfo != nil else { return }
        let clamped = min(max(progress, 0), 1)
        updateInfo?.phase = .downloading
        updateInfo?.progress = clamped
        updateInfo?.statusText = "正在下载 \(Int(clamped * 100))%"
        relayout()
    }

    func setUpdateReady() {
        guard updateInfo != nil else { return }
        updateInfo?.phase = .readyToRestart
        updateInfo?.progress = 1
        updateInfo?.statusText = "新版已就绪，重启后生效"
        dismissedUpdateBannerVersion = nil
        relayout()
    }

    func setUpdateInstalling() {
        guard updateInfo != nil else { return }
        updateInfo?.phase = .installing
        updateInfo?.statusText = "正在重启应用..."
    }

    func setUpdateError(_ message: String) {
        if Self.isUpToDateMessage(message) {
            setUpdateUpToDate()
            return
        }
        updateInfo = AppUpdateInfo(
            version: updateInfo?.version ?? "",
            title: "更新失败",
            notes: updateInfo?.notes ?? "",
            phase: .error,
            progress: 0,
            statusText: message
        )
        dismissedUpdateBannerVersion = nil
        relayout()
    }

    static func isUpToDateMessage(_ message: String) -> Bool {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.contains("up to date") ||
            value.contains("already up-to-date") ||
            value.contains("already up to date") ||
            value.contains("当前已经是最新版本") ||
            value.contains("已经是最新版本") ||
            value.contains("已是最新版本")
    }

    func setUpdateUpToDate() {
        updateInfo = AppUpdateInfo(
            version: "",
            title: "你的应用已经是最新版本",
            notes: "",
            phase: .upToDate,
            progress: 0,
            statusText: "无需更新。"
        )
        dismissedUpdateBannerVersion = nil
        relayout()
    }

    func clearUpdate() {
        updateInfo = nil
        dismissedUpdateBannerVersion = nil
        relayout()
    }

    func setPanelTab(_ t: PanelTab) {
        panelTab = t
        showingArchive = false
        relayout()
    }

    func selectList(_ id: String) {
        guard lists.contains(where: { $0.id == id }) else { return }
        selectedListId = id
        panelTab = .today
        showingArchive = false
        relayout()
    }

    func submit() {
        addTodoLines(draft, listId: selectedListId)
        draft = ""
    }

    func addTodoLines(_ raw: String, listId: String = defaultChecklistId) {
        let lines = splitLines(raw)
        guard !lines.isEmpty else { return }
        let target = lists.contains(where: { $0.id == listId }) ? listId : defaultChecklistId
        for line in lines.reversed() {
            let parsed = parseTodoLine(line)
            todos.insert(Todo(text: parsed.text, listId: target, tags: parsed.tags), at: 0)
            ensureTags(parsed.tags)
        }
        persistAll()
        relayout()
    }

    func importClipboardToTodos() {
        guard !lastClipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        addTodoLines(lastClipboardText, listId: selectedListId)
        panelTab = .today
        selectedListId = lists.first?.id ?? selectedListId
        mode = .panel
        relayout()
    }

    func updateClipboard(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        lastClipboardText = value
    }

    func complete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }), !todos[i].done else { return }
        todos[i].done = true
        todos[i].trashed = false
        todos[i].completedAt = Date()
        arm(id: todo.id, kind: .completed, item: todos[i], afterId: i > 0 ? todos[i - 1].id : nil)
        persistAll()
        relayout()
    }

    func delete(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        var item = todos[i]
        item.trashed = true
        let after = i > 0 ? todos[i - 1].id : nil
        todos.remove(at: i)
        arm(id: item.id, kind: .deleted, item: item, afterId: after)
        persistAll()
        relayout()
    }

    func deleteImmediately(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }
        pending[todo.id]?.work.cancel()
        pending[todo.id] = nil
        pendingOrder.removeAll { $0 == todo.id }
        persistAll()
        relayout()
    }

    func moveTodo(_ todo: Todo, to listId: String) {
        guard lists.contains(where: { $0.id == listId }),
              let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].listId = listId
        panelTab = .today
        showingArchive = false
        persistAll()
        relayout()
    }

    func moveToCollect(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        let item = todos.remove(at: i)
        let index = collects.firstIndex { !$0.pinned } ?? collects.count
        collects.insert(CollectItem(text: item.text), at: index)
        persistAll()
        relayout()
    }

    private func arm(id: UUID, kind: UndoKind, item: Todo, afterId: UUID?) {
        pending[id]?.work.cancel()
        pendingOrder.removeAll { $0 == id }
        pendingOrder.append(id)
        let work = DispatchWorkItem { [weak self] in self?.expire(id) }
        pending[id] = Pending(kind: kind, item: item, collectItem: nil, afterId: afterId, collectIndex: nil, work: work)
        undoVersion &+= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + undoWindow, execute: work)
    }

    private func armCollect(_ item: CollectItem, index: Int) {
        pending[item.id]?.work.cancel()
        pendingOrder.removeAll { $0 == item.id }
        pendingOrder.append(item.id)
        let work = DispatchWorkItem { [weak self] in self?.expire(item.id) }
        pending[item.id] = Pending(kind: .collectDeleted, item: nil, collectItem: item, afterId: nil, collectIndex: index, work: work)
        undoVersion &+= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + undoWindow, execute: work)
    }

    private func expire(_ id: UUID) {
        guard let p = pending[id] else { return }
        if p.kind == .completed, let done = todos.first(where: { $0.id == id && $0.done }) {
            completedArchive.insert(done, at: 0)
            todos.removeAll { $0.id == id && $0.done }
        } else if p.kind == .deleted, let item = p.item {
            completedArchive.insert(item, at: 0)
        }
        pending[id] = nil
        pendingOrder.removeAll { $0 == id }
        undoVersion &+= 1
        persistAll()
        relayout()
    }

    func performUndo() {
        guard let id = pendingOrder.last, let p = pending[id] else { return }
        p.work.cancel()
        switch p.kind {
        case .completed:
            if let i = todos.firstIndex(where: { $0.id == id }) {
                todos[i].done = false
                todos[i].completedAt = nil
            }
        case .deleted:
            if let item = p.item {
                todos.insert(item, at: insertIndex(afterId: p.afterId))
            }
        case .collectDeleted:
            if let item = p.collectItem {
                let index = min(max(p.collectIndex ?? 0, 0), collects.count)
                collects.insert(item, at: index)
                panelTab = .collect
            }
        }
        pending[id] = nil
        pendingOrder.removeAll { $0 == id }
        undoVersion &+= 1
        persistAll()
        relayout()
    }

    private func insertIndex(afterId: UUID?) -> Int {
        guard let after = afterId, let idx = todos.firstIndex(where: { $0.id == after }) else { return 0 }
        return min(idx + 1, todos.count)
    }

    func togglePin(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].pinned.toggle()
        persistAll()
        relayout()
    }

    func updateText(_ id: UUID, _ text: String) {
        let parsed = parseTodoLine(text)
        if let i = todos.firstIndex(where: { $0.id == id }) {
            guard !parsed.text.isEmpty else {
                deleteImmediately(todos[i])
                return
            }
            todos[i].text = parsed.text
            todos[i].tags = uniqueTags(todos[i].tags + parsed.tags)
            ensureTags(todos[i].tags)
            persistAll()
            return
        }

        guard let i = completedArchive.firstIndex(where: { $0.id == id }) else { return }
        guard !parsed.text.isEmpty else {
            completedArchive[i].trashed = true
            persistAll()
            relayout()
            return
        }
        completedArchive[i].text = parsed.text
        completedArchive[i].tags = uniqueTags(completedArchive[i].tags + parsed.tags)
        ensureTags(completedArchive[i].tags)
        persistAll()
    }

    func removeTagFromTodo(_ id: UUID, tag: String) {
        if let i = todos.firstIndex(where: { $0.id == id }) {
            todos[i].tags.removeAll { $0 == tag }
            persistAll()
            relayout()
        } else if let i = completedArchive.firstIndex(where: { $0.id == id }) {
            completedArchive[i].tags.removeAll { $0 == tag }
            persistAll()
            relayout()
        }
    }

    func moveActiveItem(_ id: UUID, to toIndex: Int) {
        var disp = active
        guard let from = disp.firstIndex(where: { $0.id == id }) else { return }
        let pinned = disp[from].pinned
        let lo = disp.firstIndex(where: { $0.pinned == pinned }) ?? 0
        let hi = disp.lastIndex(where: { $0.pinned == pinned }) ?? (disp.count - 1)
        let to = min(max(toIndex, lo), hi)
        guard to != from else { return }
        disp.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        todos = disp + todos.filter { $0.done || $0.listId != selectedListId }
        persistAll()
        relayout()
    }

    func submitCollect() {
        let v = collectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let index = collects.firstIndex { !$0.pinned } ?? collects.count
        collects.insert(CollectItem(text: v), at: index)
        collectDraft = ""
        persistAll()
        relayout()
    }

    func updateCollectText(_ id: UUID, _ text: String) {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, let i = collects.firstIndex(where: { $0.id == id }) else { return }
        collects[i].text = v
        persistAll()
    }

    func deleteCollect(_ id: UUID) {
        guard let index = collects.firstIndex(where: { $0.id == id }) else { return }
        let item = collects.remove(at: index)
        armCollect(item, index: index)
        persistAll()
        relayout()
    }

    func toggleCollectPin(_ id: UUID) {
        guard let index = collects.firstIndex(where: { $0.id == id }) else { return }
        var item = collects.remove(at: index)
        item.pinned.toggle()
        if item.pinned {
            collects.insert(item, at: 0)
        } else {
            let firstUnpinned = collects.firstIndex { !$0.pinned } ?? collects.count
            collects.insert(item, at: firstUnpinned)
        }
        persistAll()
        relayout()
    }

    func moveCollectToTodo(_ id: UUID, to listId: String) {
        guard lists.contains(where: { $0.id == listId }),
              let index = collects.firstIndex(where: { $0.id == id }) else { return }
        let item = collects.remove(at: index)
        let parsed = parseTodoLine(item.text)
        let text = parsed.text.isEmpty ? item.text : parsed.text
        todos.insert(Todo(text: text, listId: listId, tags: parsed.tags), at: 0)
        ensureTags(parsed.tags)
        selectedListId = listId
        panelTab = .today
        showingArchive = false
        persistAll()
        relayout()
    }

    func toggleCollectSensitive(_ id: UUID) {
        guard let i = collects.firstIndex(where: { $0.id == id }) else { return }
        collects[i].sensitive.toggle()
        persistAll()
    }

    func addList(named raw: String = "新清单") {
        let name = uniqueListName(raw)
        let list = Checklist(name: name)
        lists.append(list)
        selectedListId = list.id
        panelTab = .today
        persistAll()
        relayout()
    }

    func addTag(named raw: String = "新标签") {
        let name = uniqueTagName(raw)
        ensureTags([name])
        persistAll()
    }

    func renameTag(id: String, to raw: String) {
        let newName = TodoTag.normalize(raw)
        guard !newName.isEmpty, let i = tags.firstIndex(where: { $0.id == id }) else { return }
        let oldName = tags[i].name
        tags[i] = TodoTag(id: tags[i].id, name: newName, createdAt: tags[i].createdAt, pinned: tags[i].pinned)
        for idx in todos.indices {
            todos[idx].tags = todos[idx].tags.map { $0 == oldName ? newName : $0 }
        }
        for idx in completedArchive.indices {
            completedArchive[idx].tags = completedArchive[idx].tags.map { $0 == oldName ? newName : $0 }
        }
        persistAll()
        relayout()
    }

    func deleteTag(id: String) {
        guard let tag = tags.first(where: { $0.id == id }) else { return }
        tags.removeAll { $0.id == id }
        for idx in todos.indices {
            todos[idx].tags.removeAll { $0 == tag.name }
        }
        for idx in completedArchive.indices {
            completedArchive[idx].tags.removeAll { $0 == tag.name }
        }
        persistAll()
        relayout()
    }

    func mergeTag(id: String, into rawTargetName: String) {
        let targetName = TodoTag.normalize(rawTargetName)
        guard let sourceIndex = tags.firstIndex(where: { $0.id == id }),
              let target = tags.first(where: { $0.name == targetName }),
              tags[sourceIndex].name != target.name else { return }
        let sourceName = tags[sourceIndex].name
        for index in todos.indices {
            todos[index].tags = uniqueTags(todos[index].tags.map { $0 == sourceName ? target.name : $0 })
        }
        for index in completedArchive.indices {
            completedArchive[index].tags = uniqueTags(completedArchive[index].tags.map { $0 == sourceName ? target.name : $0 })
        }
        tags.remove(at: sourceIndex)
        persistAll()
        relayout()
    }

    func toggleTagPinned(id: String) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        var tag = tags.remove(at: index)
        tag.pinned.toggle()
        let insertionIndex = tags.firstIndex(where: { !$0.pinned }) ?? tags.count
        tags.insert(tag, at: insertionIndex)
        persistAll()
        relayout()
    }

    func moveTag(_ sourceID: String, _ targetID: String) {
        guard let sourceIndex = tags.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = tags.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else { return }
        tags.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        persistAll()
        relayout()
    }

    func completedItems(includeTrash: Bool = false) -> [Todo] {
        let live = todos.filter { $0.done && (includeTrash || !$0.trashed) }
        let archived = completedArchive.filter { includeTrash || !$0.trashed }
        return (live + archived).sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    func trashedItems() -> [Todo] {
        completedArchive.filter(\.trashed)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
    }

    func updateSummaryTemplate(_ id: String) {
        guard settings.summaryTemplates.contains(where: { $0.id == id }) else { return }
        updateSettings { $0.activeSummaryTemplateId = id }
    }

    func renameList(id: String, to raw: String) {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[i].name = name
        persistAll()
        relayout()
    }

    func toggleListPinned(id: String) {
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        var list = lists.remove(at: index)
        list.pinned.toggle()
        let insertionIndex = lists.firstIndex(where: { !$0.pinned }) ?? lists.count
        lists.insert(list, at: insertionIndex)
        persistAll()
        relayout()
    }

    func moveList(_ sourceID: String, _ targetID: String) {
        guard let sourceIndex = lists.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = lists.firstIndex(where: { $0.id == targetID }),
              sourceIndex != targetIndex else { return }
        lists.move(
            fromOffsets: IndexSet(integer: sourceIndex),
            toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        )
        persistAll()
        relayout()
    }

    func listHasTodos(id: String) -> Bool {
        todos.contains { $0.listId == id } || completedArchive.contains { $0.listId == id }
    }

    func deleteList(id: String) {
        guard lists.contains(where: { $0.id == id }) else { return }
        lists.removeAll { $0.id == id }
        todos.removeAll { $0.listId == id }
        completedArchive.removeAll { $0.listId == id }
        if lists.isEmpty {
            let replacement = Checklist(name: "新清单")
            lists = [replacement]
            selectedListId = replacement.id
        } else if selectedListId == id {
            selectedListId = lists[0].id
        }
        var updated = settings
        updated.summaryListIds.removeAll { $0 == id }
        for i in updated.summaryTemplates.indices {
            updated.summaryTemplates[i].listIds.removeAll { $0 == id }
        }
        settings = updated
        persistAll()
        relayout()
    }

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        updated.summonHotkeyIndex = normalizedIndex(updated.summonHotkeyIndex, count: Settings.hotkeyOptions.count)
        updated.quickRecordHotkeyIndex = normalizedIndex(updated.quickRecordHotkeyIndex, count: Settings.quickRecordHotkeyOptions.count)
        updated.normalize()
        settings = updated
    }

    func toggleWindowPinned() {
        windowPinned.toggle()
        UserDefaults.standard.set(windowPinned, forKey: windowPinnedKey)
        onPinnedChanged?(windowPinned)
        relayout()
    }

    func makeSummary() {
        showSummaryToast("准备总结…", autoHideAfter: nil)
        let template = settings.activeSummaryTemplate
        let content = summarySourceMarkdown(template: template)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showSummaryToast("当前总结范围内没有可总结内容", autoHideAfter: 3)
            return
        }
        let prompt = template.prompt.replacingOccurrences(of: "{{content}}", with: content)
        showSummaryToast("总结中…", autoHideAfter: nil)
        SummaryService.summarize(settings: settings, prompt: prompt) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let result):
                    if let quota = result.quota {
                        self.presetQuota = quota
                        self.presetQuotaStatus = nil
                    }
                    self.copyToClipboard(result.text)
                    let summary = SummaryRecord(text: result.text)
                    self.summaries.insert(summary, at: 0)
                    self.latestGeneratedSummaryID = summary.id
                    SummaryRecordStore.save(self.summaries)
                    self.summaryStatus = nil
                    self.showSummaryToast("生成完成，已复制剪贴板", autoHideAfter: 5)
                    self.persistAll()
                case .failure(let error):
                    self.summaryStatus = nil
                    self.showSummaryToast(error.localizedDescription, autoHideAfter: 5)
                }
            }
        }
    }

    func refreshPresetQuota() {
        guard settings.activeModel?.isAppPreset == true else {
            presetQuotaStatus = nil
            return
        }
        guard !isPresetActivated else {
            presetQuota = nil
            presetQuotaStatus = nil
            return
        }
        presetQuotaStatus = "正在获取预设模型额度..."
        SummaryService.fetchPresetQuota { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let quota):
                    self.presetQuota = quota
                    self.presetQuotaStatus = nil
                case .failure:
                    self.presetQuotaStatus = "暂时无法获取预设模型额度"
                }
            }
        }
    }

    func activatePreset(using code: String) -> Bool {
        guard PresetActivation.activate(using: code) else { return false }
        isPresetActivated = true
        presetQuota = nil
        presetQuotaStatus = nil
        return true
    }

    private func showSummaryToast(_ message: String, autoHideAfter seconds: TimeInterval?) {
        summaryToastWork?.cancel()
        summaryToast = message
        guard let seconds else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.summaryToast = nil
        }
        summaryToastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func toggleArchiveView() {
        panelTab = .today
        showingArchive.toggle()
        relayout()
    }

    func restoreFromArchive(_ todo: Todo) {
        guard let i = completedArchive.firstIndex(where: { $0.id == todo.id }) else { return }
        var restored = completedArchive.remove(at: i)
        restored.done = false
        restored.trashed = false
        restored.completedAt = nil
        if !lists.contains(where: { $0.id == restored.listId }) {
            restored.listId = defaultChecklistId
        }
        todos.insert(restored, at: 0)
        selectedListId = restored.listId
        panelTab = .today
        showingArchive = false
        persistAll()
        relayout()
    }

    func restoreCompleted(_ todo: Todo) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index].done = false
            todos[index].completedAt = nil
            persistAll()
            relayout()
        } else {
            restoreFromArchive(todo)
        }
    }

    func moveCompletedToTrash(_ todo: Todo) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            var trashed = todos.remove(at: index)
            trashed.trashed = true
            completedArchive.insert(trashed, at: 0)
        } else if let index = completedArchive.firstIndex(where: { $0.id == todo.id }) {
            completedArchive[index].trashed = true
        }
        persistAll()
        relayout()
    }

    func deleteFromArchive(_ todo: Todo) {
        completedArchive.removeAll { $0.id == todo.id }
        persistAll()
        relayout()
    }

    func clearArchive() {
        completedArchive.removeAll()
        showingArchive = false
        persistAll()
        relayout()
    }

    func openMarkdownFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([MarkdownExporter.fileURL])
    }

    func persistAll() {
        TodoStore.save(todos.filter { !$0.done })
        CompletedTodoStore.save(completedArchive)
        CollectStore.save(collects)
        ChecklistStore.save(lists)
        SummaryRecordStore.save(summaries)
        TagStore.save(tags)
        MarkdownExporter.export(lists: lists, todos: todos, completedArchive: completedArchive, collects: collects, summaries: summaries, settings: settings)
    }

    private func splitLines(_ raw: String) -> [String] {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseTodoLine(_ raw: String) -> (text: String, tags: [String]) {
        var kept: [String] = []
        var found: [String] = []
        for part in raw.components(separatedBy: .whitespacesAndNewlines) {
            let tag = TodoTag.normalize(part)
            if part.hasPrefix("#"), !tag.isEmpty {
                found.append(tag)
            } else if !part.isEmpty {
                kept.append(part)
            }
        }
        return (kept.joined(separator: " "), uniqueTags(found))
    }

    private func ensureTags(_ names: [String]) {
        var existingNames = Set(tags.map(\.name))
        for name in names.map(TodoTag.normalize) where !name.isEmpty {
            if existingNames.insert(name).inserted {
                tags.append(TodoTag(name: name))
            }
        }
    }

    private func syncTagsFromTodos() {
        ensureTags((todos + completedArchive).flatMap(\.tags))
    }

    private func uniqueTags(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names
            .map(TodoTag.normalize)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private func uniqueTagName(_ raw: String) -> String {
        let base = TodoTag.normalize(raw).isEmpty ? "新标签" : TodoTag.normalize(raw)
        var name = base
        var i = 2
        while tags.contains(where: { $0.name == name }) {
            name = "\(base) \(i)"
            i += 1
        }
        return name
    }

    private func uniqueListName(_ raw: String) -> String {
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新清单" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = base
        var i = 2
        while lists.contains(where: { $0.name == name }) {
            name = "\(base) \(i)"
            i += 1
        }
        return name
    }

    private func normalizedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    private func applyLaunchAtLogin() {
        do {
            let enabled = SMAppService.mainApp.status == .enabled
            if settings.launchAtLogin, !enabled { try SMAppService.mainApp.register() }
            if !settings.launchAtLogin, enabled { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("launch-at-login apply failed: \(error.localizedDescription)")
        }
    }

    private func summarySourceMarkdown(template: SummaryTemplateConfig) -> String {
        let interval = DateRange.period(template.period)
        let selected = Set(template.listIds.isEmpty ? lists.map(\.id) : template.listIds)
        var lines: [String] = []
        for list in lists where selected.contains(list.id) {
            let activeItems = todos.filter { !$0.done && $0.listId == list.id && interval.contains($0.createdAt) }
            let doneItems = (todos.filter { $0.done } + completedArchive)
                .filter { $0.listId == list.id && interval.contains($0.completedAt ?? $0.createdAt) }
            guard !activeItems.isEmpty || !doneItems.isEmpty else { continue }
            lines.append("## \(list.name)")
            for item in activeItems { lines.append(summaryLine(item, checked: false)) }
            for item in doneItems { lines.append(summaryLine(item, checked: true)) }
            lines.append("")
        }
        if template.includeCollects, !collects.isEmpty {
            lines.append("## 收藏")
            for item in collects { lines.append("- \(item.text)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func summaryLine(_ item: Todo, checked: Bool) -> String {
        let marker = checked ? "[x]" : "[ ]"
        let project = item.tags.isEmpty ? "" : "（项目：\(item.tags.joined(separator: "、"))）"
        return "- \(marker) \(item.text)\(project)"
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastClipboardText = text
    }
}

enum DateRange {
    static func period(_ period: SummaryPeriod, now: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        let start: Date
        switch period {
        case .today:
            start = cal.startOfDay(for: now)
        case .week:
            start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        case .month:
            start = cal.dateInterval(of: .month, for: now)?.start ?? cal.startOfDay(for: now)
        case .quarter:
            let comps = cal.dateComponents([.year, .month], from: now)
            let month = comps.month ?? 1
            let quarterStart = ((month - 1) / 3) * 3 + 1
            start = cal.date(from: DateComponents(year: comps.year, month: quarterStart, day: 1)) ?? cal.startOfDay(for: now)
        case .halfYear:
            let comps = cal.dateComponents([.year, .month], from: now)
            let halfStart = (comps.month ?? 1) <= 6 ? 1 : 7
            start = cal.date(from: DateComponents(year: comps.year, month: halfStart, day: 1)) ?? cal.startOfDay(for: now)
        case .year:
            start = cal.dateInterval(of: .year, for: now)?.start ?? cal.startOfDay(for: now)
        }
        return DateInterval(start: start, end: now.addingTimeInterval(1))
    }
}
