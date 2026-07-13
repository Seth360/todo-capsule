import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var section: SettingsSection = .general
    @State private var editingModel: ModelConfig?
    @State private var editingSummary: SummaryTemplateConfig?
    @State private var recordingHotkey: HotkeyFieldKind?
    @State private var showingPresetActivation = false

    private var preferredScheme: ColorScheme? {
        switch state.settings.theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(section.title)
                            .font(.tc(24, weight: .semibold))
                        Spacer()
                        headerAction
                    }
                    sectionBody
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay(alignment: .bottomTrailing) {
                if section == .model {
                    Button {
                        showingPresetActivation = true
                    } label: {
                        Label(state.isPresetActivated ? "已激活" : "一键激活", systemImage: state.isPresetActivated ? "checkmark.seal.fill" : "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: 0x32D158))
                    .controlSize(.large)
                    .disabled(state.isPresetActivated)
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(preferredScheme)
        .sheet(item: $editingModel) { model in
            ModelEditorView(initial: model, onSave: saveModel)
                .frame(width: 520, height: 520)
        }
        .sheet(item: $editingSummary) { template in
            SummaryTemplateEditorView(initial: template, lists: state.lists, onSave: saveSummaryTemplate)
                .frame(width: 560, height: 600)
        }
        .sheet(item: $recordingHotkey) { kind in
            HotkeyRecorderSheet(
                title: kind.title,
                onCancel: { recordingHotkey = nil },
                onSave: { option in
                    switch kind {
                    case .summon:
                        state.settings.summonHotkey = option
                    case .quickRecord:
                        state.settings.quickRecordHotkey = option
                    }
                    recordingHotkey = nil
                }
            )
            .frame(width: 380, height: 230)
        }
        .sheet(isPresented: $showingPresetActivation) {
            PresetActivationView { code in
                state.activatePreset(using: code)
            }
            .frame(width: 430, height: 250)
        }
        .onAppear {
            if section == .model { state.refreshPresetQuota() }
        }
        .onChange(of: section) { _, newSection in
            if newSection == .model { state.refreshPresetQuota() }
        }
    }

    private var versionLabel: some View {
        Text(appVersionText)
            .font(.tc(11, weight: .medium))
            .foregroundStyle(.secondary.opacity(0.72))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .allowsHitTesting(false)
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let displayVersion = if let version, !version.isEmpty { version } else { "未知" }
        guard let build, !build.isEmpty else { return "版本 \(displayVersion)" }
        return "版本 \(displayVersion) (\(build))"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.title)
                        Spacer()
                    }
                    .font(.tc(14, weight: section == item ? .semibold : .regular))
                    .foregroundStyle(section == item ? Color.primary : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(section == item ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if state.shouldShowSettingsUpdateNotice {
                settingsUpdateNotice
            } else {
                versionLabel
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.92))
    }

    private var settingsUpdateNotice: some View {
        Button {
            state.openUpdateDialog()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Color(hex: 0x32D158))
                    Text("发现新版本")
                        .font(.tc(14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                if let version = settingsUpdateVersion {
                    Text(version)
                        .font(.tc(11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: 0x32D158).opacity(0.13))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color(hex: 0x32D158).opacity(0.36), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var settingsUpdateVersion: String? {
        guard let info = state.updateInfo, !info.version.isEmpty else { return nil }
        return "版本 \(info.version)"
    }

    @ViewBuilder
    private var headerAction: some View {
        switch section {
        case .model:
            Button {
                editingModel = ModelConfig(title: "", providerName: "", baseURL: "", apiKey: "", modelName: "")
            } label: {
                Label("新建", systemImage: "plus")
            }
        case .summary:
            Button {
                editingSummary = SummaryTemplateConfig(title: "新模板", period: .week, listIds: [defaultChecklistId], includeCollects: false, prompt: "{{content}}")
            } label: {
                Label("新建", systemImage: "plus")
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .general: generalSection
        case .hotkeys: hotkeySection
        case .lists: listsSection
        case .tags: tagsSection
        case .model: modelSection
        case .summary: summarySection
        case .export: exportSection
        }
    }

    private var generalSection: some View {
        Form {
            Toggle("开机自动启动", isOn: $state.settings.launchAtLogin)
            Picker("语言", selection: $state.settings.language) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
            Picker("主题", selection: $state.settings.theme) {
                ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
            }
            Text("小窗可直接拖动，松开后会自动吸附到屏幕左侧或右侧。")
                .font(.tc(12))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var hotkeySection: some View {
        Form {
            HotkeyPickerRow(
                title: "唤起方式",
                selection: Binding(
                    get: { state.settings.summonHotkey ?? Settings.hotkeyOptions[0] },
                    set: { state.settings.summonHotkey = $0 }
                ),
                presets: Settings.hotkeyOptions,
                onCustom: { recordingHotkey = .summon }
            )
            HotkeyPickerRow(
                title: "快速记录",
                selection: Binding(
                    get: { state.settings.quickRecordHotkey ?? Settings.quickRecordHotkeyOptions[0] },
                    set: { state.settings.quickRecordHotkey = $0 }
                ),
                presets: Settings.quickRecordHotkeyOptions,
                onCustom: { recordingHotkey = .quickRecord }
            )
            Text("快速将复制文字回填到待办")
                .font(.tc(12))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            listRow(name: "待办", icon: "list.bullet", isEditable: false, binding: .constant("待办"), onDelete: nil)
            listRow(name: "收藏", icon: "bookmark", isEditable: false, binding: .constant("收藏"), onDelete: nil)
            ForEach(state.lists.filter { $0.id != defaultChecklistId }) { list in
                listRow(
                    name: list.name,
                    icon: "list.bullet",
                    isEditable: true,
                    binding: Binding(
                        get: { list.name },
                        set: { state.renameList(id: list.id, to: $0) }
                    ),
                    onDelete: { state.deleteList(id: list.id) }
                )
            }
            Button {
                state.addList(named: "新清单")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").frame(width: 18)
                    Text("新增清单")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 620)
    }

    private func listRow(name: String, icon: String, isEditable: Bool, binding: Binding<String>, onDelete: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            if isEditable {
                TextField("清单名称", text: binding)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(name)
                    .font(.tc(14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除清单")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.14)))
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.tags.isEmpty {
                Text("还没有标签。录入待办时输入 #项目名 会自动保存到这里。")
                    .font(.tc(12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            ForEach(state.tags) { tag in
                tagRow(
                    binding: Binding(
                        get: { tag.name },
                        set: { state.renameTag(id: tag.id, to: $0) }
                    ),
                    onDelete: { state.deleteTag(id: tag.id) }
                )
            }
            Button {
                state.addTag(named: "新标签")
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").frame(width: 18)
                    Text("新增标签")
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 620)
    }

    private func tagRow(binding: Binding<String>, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "number")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("标签名称", text: binding)
                .textFieldStyle(.roundedBorder)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("删除标签")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.14)))
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.settings.models) { model in
                if model.isAppPreset && state.settings.activeModelId == model.id {
                    if state.isPresetActivated {
                        PresetActivatedView()
                    } else {
                        PresetQuotaView(quota: state.presetQuota, status: state.presetQuotaStatus)
                            .onAppear { state.refreshPresetQuota() }
                    }
                }
                ModelCard(
                    model: model,
                    active: state.settings.activeModelId == model.id,
                    presetActivated: state.isPresetActivated,
                    onEnable: { enableModel(model.id) },
                    onEdit: { editingModel = model },
                    onDuplicate: { duplicateModel(model) },
                    onDelete: { deleteModel(model.id) }
                )
            }
        }
        .padding(.bottom, 58)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.settings.summaryTemplates) { template in
                SummaryTemplateCard(
                    template: template,
                    listNames: summaryListNames(template),
                    active: state.settings.activeSummaryTemplateId == template.id,
                    onEnable: { enableSummaryTemplate(template.id) },
                    onEdit: { editingSummary = template },
                    onDelete: { deleteSummaryTemplate(template.id) }
                )
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                HStack {
                    Text("Markdown 文件")
                    Spacer()
                    Text(MarkdownExporter.fileURL.path)
                        .font(.tc(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack {
                    TextField("Obsidian Vault 路径", text: $state.settings.obsidianVaultPath)
                    Button("选择") { chooseObsidianFolder() }
                }
                Toggle("同步到 Mac 备忘录", isOn: $state.settings.syncAppleNotes)
            }
            .formStyle(.grouped)
            Button("立即导出") { state.persistAll() }
        }
    }

    private func enableModel(_ id: String) {
        state.updateSettings { $0.activeModelId = id }
        if state.settings.models.first(where: { $0.id == id })?.isAppPreset == true {
            state.refreshPresetQuota()
        }
    }

    private func duplicateModel(_ model: ModelConfig) {
        guard !model.isAppPreset else { return }
        var copy = model
        copy.id = UUID().uuidString
        copy.title = "\(model.title) 副本"
        state.updateSettings { $0.models.append(copy) }
    }

    private func deleteModel(_ id: String) {
        state.updateSettings { settings in
            guard settings.models.first(where: { $0.id == id })?.isAppPreset != true else { return }
            settings.models.removeAll { $0.id == id }
            if settings.models.isEmpty { settings.models = ModelConfig.defaults }
            if settings.activeModelId == id { settings.activeModelId = settings.models.first?.id ?? "" }
        }
    }

    private func saveModel(_ model: ModelConfig) {
        guard !model.isAppPreset else { return }
        state.updateSettings { settings in
            if let i = settings.models.firstIndex(where: { $0.id == model.id }) {
                settings.models[i] = model
            } else {
                settings.models.append(model)
            }
            settings.activeModelId = model.id
        }
    }

    private func enableSummaryTemplate(_ id: String) {
        state.updateSettings { settings in
            settings.activeSummaryTemplateId = id
            for i in settings.summaryTemplates.indices {
                settings.summaryTemplates[i].isEnabled = settings.summaryTemplates[i].id == id
            }
        }
    }

    private func deleteSummaryTemplate(_ id: String) {
        state.updateSettings { settings in
            settings.summaryTemplates.removeAll { $0.id == id }
            if settings.summaryTemplates.isEmpty { settings.summaryTemplates = [.week, .halfYear] }
            if settings.activeSummaryTemplateId == id { settings.activeSummaryTemplateId = settings.summaryTemplates.first?.id ?? "" }
        }
    }

    private func saveSummaryTemplate(_ template: SummaryTemplateConfig) {
        state.updateSettings { settings in
            var saved = template
            saved.prompt = String(saved.prompt.prefix(summaryPromptCharacterLimit))
            if let i = settings.summaryTemplates.firstIndex(where: { $0.id == template.id }) {
                settings.summaryTemplates[i] = saved
            } else {
                settings.summaryTemplates.append(saved)
            }
            if saved.isEnabled {
                settings.activeSummaryTemplateId = saved.id
                for i in settings.summaryTemplates.indices {
                    settings.summaryTemplates[i].isEnabled = settings.summaryTemplates[i].id == saved.id
                }
            }
        }
    }

    private func summaryListNames(_ template: SummaryTemplateConfig) -> String {
        var names = state.lists.filter { template.listIds.contains($0.id) }.map(\.name)
        if template.includeCollects { names.append("收藏") }
        return names.isEmpty ? "全部清单" : names.joined(separator: "、")
    }

    private func chooseObsidianFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.settings.obsidianVaultPath = url.path
        }
    }
}

private enum HotkeyFieldKind: String, Identifiable {
    case summon
    case quickRecord

    var id: String { rawValue }
    var title: String {
        switch self {
        case .summon: return "自定义唤起方式"
        case .quickRecord: return "自定义快速记录"
        }
    }
}

private struct HotkeyPickerRow: View {
    let title: String
    @Binding var selection: HotkeyOption
    let presets: [HotkeyOption]
    let onCustom: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu {
                Button {
                    selection = Settings.noHotkey
                } label: {
                    hotkeyMenuLabel(title: "无", systemImage: "minus.circle", selected: selection.isEmpty)
                }
                Divider()
                ForEach(presets, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        hotkeyMenuLabel(title: option.name, systemImage: "keyboard", selected: selection == option)
                    }
                }
                Divider()
                Button(action: onCustom) {
                    Label("自定义快捷键…", systemImage: "keyboard.badge.ellipsis")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.tc(12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(selection.name)
                        .font(.tc(13, weight: .semibold))
                        .monospaced()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.tc(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.secondary.opacity(0.10)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private func hotkeyMenuLabel(title: String, systemImage: String, selected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: selected ? "checkmark" : systemImage)
        }
    }
}

private struct HotkeyRecorderSheet: View {
    let title: String
    let onCancel: () -> Void
    let onSave: (HotkeyOption) -> Void
    @State private var captured: HotkeyOption?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.tc(20, weight: .semibold))
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                VStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.tc(22, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x32D158))
                    Text(captured?.name ?? "按下新的快捷键")
                        .font(.tc(18, weight: .semibold))
                        .monospaced()
                    Text("可包含 Option、Command、Control、Shift")
                        .font(.tc(12))
                        .foregroundStyle(.secondary)
                }
                HotkeyCaptureView { event in
                    let modifiers = Settings.carbonModifiers(from: event.modifierFlags)
                    let keyCode = UInt32(event.keyCode)
                    guard keyCode != 0 else { return }
                    captured = HotkeyOption(
                        name: Settings.displayName(keyCode: keyCode, modifiers: modifiers),
                        keyCode: keyCode,
                        modifiers: modifiers
                    )
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
            .frame(height: 104)

            HStack {
                Button("清空") {
                    onSave(Settings.noHotkey)
                }
                Spacer()
                Button("取消") {
                    onCancel()
                }
                Button("保存") {
                    if let captured {
                        onSave(captured)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(captured == nil)
            }
        }
        .padding(22)
    }
}

private struct HotkeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyCaptureNSView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

private struct ModelCard: View {
    let model: ModelConfig
    let active: Bool
    let presetActivated: Bool
    let onEnable: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    private let activeGreen = Color(hex: 0x32D158)

    var body: some View {
        let protected = model.isAppPreset
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary.opacity(0.65))
            if !protected {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10))
                    Text(model.initial).font(.tc(13, weight: .semibold)).foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(model.displayTitle).font(.tc(17, weight: .semibold))
                if protected {
                    Text(presetActivated ? "预设模型，不限制使用次数" : "默认模型限制使用次数，可添加自有模型API")
                        .font(.tc(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(model.baseURL.isEmpty ? "未配置 Base URL" : model.baseURL)
                        .font(.tc(14))
                        .foregroundStyle(activeGreen)
                        .lineLimit(1)
                }
            }
            Spacer()
            if active {
                Label("启用中", systemImage: "checkmark.circle.fill")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(activeGreen)
            } else {
                Button(action: onEnable) {
                    Label("启用", systemImage: "play")
                }
                .buttonStyle(.borderedProminent)
                .tint(activeGreen)
            }
            if !protected {
                Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                    .help("编辑模型")
                Button(action: onDuplicate) { Image(systemName: "square.on.square") }
                    .help("复制模型")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("删除模型")
            }
        }
        .buttonStyle(.borderless)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? activeGreen.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? activeGreen.opacity(0.75) : Color.secondary.opacity(0.22), lineWidth: active ? 1.5 : 1))
    }
}

private struct PresetActivatedView: View {
    private let activeGreen = Color(hex: 0x32D158)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(activeGreen)
            Text("已激活，不限制使用次数")
                .font(.tc(14, weight: .semibold))
            Spacer()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(activeGreen.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(activeGreen.opacity(0.35)))
    }
}

private struct PresetActivationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var errorText: String?
    @FocusState private var isCodeFocused: Bool

    let onSubmit: (String) -> Bool
    private let activeGreen = Color(hex: 0x32D158)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.tc(22))
                    .foregroundStyle(activeGreen)
                Text("一键激活")
                    .font(.tc(20, weight: .semibold))
            }

            Text("激活后，使用预设模型将不再限制使用次数，无限畅饮！")
                .font(.tc(14))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                TextField("请输入激活码", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .focused($isCodeFocused)
                    .onSubmit(submit)
                if let errorText {
                    Text(errorText)
                        .font(.tc(12))
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("提交", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(activeGreen)
                    .keyboardShortcut(.defaultAction)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .onAppear { isCodeFocused = true }
    }

    private func submit() {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if onSubmit(code) {
            dismiss()
        } else {
            errorText = "激活码不正确，请重新输入。"
        }
    }
}

private struct PresetQuotaView: View {
    let quota: PresetQuota?
    let status: String?
    private let activeGreen = Color(hex: 0x32D158)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("预设模型额度", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.tc(14, weight: .semibold))
                Spacer()
                Text(quotaText)
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(activeGreen)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.16))
                    Capsule()
                        .fill(activeGreen)
                        .frame(width: max(8, proxy.size.width * CGFloat(quota?.progress ?? 0)))
                }
            }
            .frame(height: 8)
            Text(detailText)
                .font(.tc(12))
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.14)))
    }

    private var quotaText: String {
        guard let quota else { return status ?? "获取中..." }
        return "已用 \(quota.used)/\(quota.limit)"
    }

    private var detailText: String {
        guard let quota else { return status ?? "仅预设模型受每周次数限制，自建模型不受限制。" }
        return "剩余 \(quota.remaining) 次 · 每周五 24:00 重置（\(quota.resetText)）"
    }
}

private struct SummaryTemplateCard: View {
    let template: SummaryTemplateConfig
    let listNames: String
    let active: Bool
    let onEnable: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    private let activeGreen = Color(hex: 0x32D158)

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: active ? "sparkles" : "doc.text")
                .foregroundStyle(active ? activeGreen : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(template.title).font(.tc(17, weight: .semibold))
                Text("\(template.period.title) · \(listNames)")
                    .font(.tc(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if active {
                Label("启用中", systemImage: "checkmark.circle.fill")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(activeGreen)
            } else {
                Button(action: onEnable) {
                    Label("启用", systemImage: "play")
                }
                .buttonStyle(.borderedProminent)
                .tint(activeGreen)
            }
            Button(action: onEdit) { Image(systemName: "square.and.pencil") }
                .help("编辑总结模板")
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .help("删除总结模板")
        }
        .buttonStyle(.borderless)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? activeGreen.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? activeGreen.opacity(0.75) : Color.secondary.opacity(0.22), lineWidth: active ? 1.5 : 1))
    }
}

private struct ModelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ModelConfig
    @State private var selectedPresetId: String
    @State private var availableModelNames: [String]
    @State private var modelFetchStatus: String?
    @State private var isFetchingModels = false
    let onSave: (ModelConfig) -> Void

    init(initial: ModelConfig, onSave: @escaping (ModelConfig) -> Void) {
        let presetId = ModelPreset.matching(initial)?.id ?? ""
        let currentModelName = initial.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        _model = State(initialValue: initial)
        _selectedPresetId = State(initialValue: presetId)
        _availableModelNames = State(initialValue: currentModelName.isEmpty ? [] : [currentModelName])
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型配置").font(.tc(22, weight: .semibold))
            Form {
                TextField("标题", text: $model.title)
                Picker("常用模型", selection: presetSelection) {
                    Text("请选择").tag("")
                    ForEach(ModelPreset.all) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                TextField("Base URL", text: $model.baseURL)
                SecureField("API Key", text: $model.apiKey)
                HStack {
                    Text("自动获取模型")
                    Spacer()
                    Button(isFetchingModels ? "获取中..." : "获取") {
                        fetchModels()
                    }
                    .disabled(isFetchingModels || model.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !modelNameOptions.isEmpty {
                    Picker("模型", selection: modelNameSelection) {
                        ForEach(modelNameOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                }
                if let modelFetchStatus {
                    Text(modelFetchStatus)
                        .font(.tc(11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    var saved = model
                    saved.customHeaders = ""
                    if !selectedPresetId.isEmpty,
                       saved.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        saved.modelName = ModelPreset.defaultModelName(for: saved)
                    }
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }

    private var modelNameOptions: [String] {
        let current = model.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (current.isEmpty ? availableModelNames : [current] + availableModelNames).removingDuplicates()
    }

    private var presetSelection: Binding<String> {
        Binding(
            get: { selectedPresetId },
            set: { id in
                selectedPresetId = id
                guard let preset = ModelPreset.all.first(where: { $0.id == id }) else { return }
                preset.apply(to: &model)
                let currentModelName = model.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
                availableModelNames = currentModelName.isEmpty ? [] : [currentModelName]
                modelFetchStatus = nil
            }
        )
    }

    private var modelNameSelection: Binding<String> {
        Binding(
            get: { model.modelName },
            set: { model.modelName = $0 }
        )
    }

    private func fetchModels() {
        isFetchingModels = true
        modelFetchStatus = "正在获取模型列表..."
        ModelListService.fetch(baseURL: model.baseURL, apiKey: model.apiKey) { result in
            DispatchQueue.main.async {
                isFetchingModels = false
                switch result {
                case .success(let names):
                    availableModelNames = names
                    if model.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !names.contains(model.modelName) {
                        model.modelName = names[0]
                    }
                    modelFetchStatus = "已获取 \(names.count) 个模型"
                case .failure(let error):
                    modelFetchStatus = "获取失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

private struct ModelPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let providerName: String
    let baseURL: String
    let modelName: String
    let supportsRouting: Bool

    static let openAI = ModelPreset(
        id: "openai-official",
        title: "OpenAI · gpt-4.1",
        providerName: "OpenAI",
        baseURL: "https://api.openai.com",
        modelName: "gpt-4.1",
        supportsRouting: false
    )

    static let deepSeek = ModelPreset(
        id: "deepseek",
        title: "DeepSeek · deepseek-v4-flash",
        providerName: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        modelName: "deepseek-v4-flash",
        supportsRouting: true
    )

    static let qwen = ModelPreset(
        id: "qwen",
        title: "通义 · qwen-plus",
        providerName: "通义千问",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        modelName: "qwen-plus",
        supportsRouting: true
    )

    static let kimi = ModelPreset(
        id: "kimi",
        title: "Kimi · kimi-k2.6",
        providerName: "Kimi",
        baseURL: "https://api.moonshot.cn/v1",
        modelName: "kimi-k2.6",
        supportsRouting: true
    )

    static let glm = ModelPreset(
        id: "glm",
        title: "智谱 · glm-5.1",
        providerName: "智谱 GLM",
        baseURL: "https://open.bigmodel.cn/api/paas/v4",
        modelName: "glm-5.1",
        supportsRouting: true
    )

    static let custom = ModelPreset(
        id: "custom",
        title: "自定义 API（保留当前模型）",
        providerName: "Custom",
        baseURL: "",
        modelName: "",
        supportsRouting: true
    )

    static let all: [ModelPreset] = [.openAI, .deepSeek, .qwen, .kimi, .glm, .custom]

    static func matching(_ model: ModelConfig) -> ModelPreset? {
        all.first { preset in
            preset.id != custom.id &&
            preset.baseURL == model.baseURL &&
            preset.modelName == model.modelName
        } ?? (model.providerName == custom.providerName ? custom : nil)
    }

    static func defaultModelName(for model: ModelConfig) -> String {
        let hints = [
            model.providerName,
            model.title,
            model.baseURL
        ]
        .map { $0.lowercased() }
        .joined(separator: " ")

        if hints.contains("deepseek") { return deepSeek.modelName }
        if hints.contains("dashscope") || hints.contains("aliyun") || hints.contains("qwen") || hints.contains("通义") {
            return qwen.modelName
        }
        if hints.contains("moonshot") || hints.contains("kimi") { return kimi.modelName }
        if hints.contains("bigmodel") || hints.contains("zhipu") || hints.contains("glm") || hints.contains("智谱") {
            return glm.modelName
        }
        return openAI.modelName
    }

    func makeConfig() -> ModelConfig {
        ModelConfig(
            title: title.replacingOccurrences(of: " · ", with: " "),
            providerName: providerName,
            baseURL: baseURL,
            apiKey: "",
            modelName: modelName,
            supportsRouting: supportsRouting
        )
    }

    func apply(to model: inout ModelConfig) {
        model.providerName = providerName
        model.supportsRouting = supportsRouting
        model.customHeaders = ""
        guard id != Self.custom.id else {
            if model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.title = "自定义 API"
            }
            return
        }
        model.title = title.replacingOccurrences(of: " · ", with: " ")
        model.baseURL = baseURL
        model.modelName = modelName
    }
}

private struct SummaryTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: SummaryTemplateConfig
    let lists: [Checklist]
    let onSave: (SummaryTemplateConfig) -> Void
    private let promptLimit = summaryPromptCharacterLimit

    init(initial: SummaryTemplateConfig, lists: [Checklist], onSave: @escaping (SummaryTemplateConfig) -> Void) {
        _template = State(initialValue: initial)
        self.lists = lists
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("总结模板").font(.tc(22, weight: .semibold))
            Form {
                TextField("标题", text: $template.title)
                Picker("总结周期", selection: $template.period) {
                    ForEach(SummaryPeriod.allCases) { Text($0.title).tag($0) }
                }
                Toggle("启用此模板", isOn: $template.isEnabled)
                Section("总结范围") {
                    ForEach(lists) { list in
                        Toggle(list.name, isOn: listBinding(list.id))
                    }
                    Toggle("收藏", isOn: $template.includeCollects)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("总结模板（提示词）")
                    TextEditor(text: promptBinding)
                        .font(.tc(12))
                        .frame(height: 180)
                    HStack {
                        Text("使用 {{content}} 作为待办内容占位符。")
                        Spacer()
                        Text("\(template.prompt.count)/\(promptLimit)")
                            .foregroundStyle(template.prompt.count >= promptLimit ? .red : .secondary)
                    }
                    .font(.tc(11))
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    template.prompt = String(template.prompt.prefix(promptLimit))
                    onSave(template)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
    }

    private func listBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { template.listIds.contains(id) },
            set: { enabled in
                if enabled {
                    if !template.listIds.contains(id) { template.listIds.append(id) }
                } else {
                    template.listIds.removeAll { $0 == id }
                }
            }
        )
    }

    private var promptBinding: Binding<String> {
        Binding(
            get: { template.prompt },
            set: { template.prompt = String($0.prefix(promptLimit)) }
        )
    }
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, hotkeys, lists, tags, model, summary, export
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .hotkeys: return "快捷键"
        case .lists: return "清单"
        case .tags: return "标签管理"
        case .model: return "模型设置"
        case .summary: return "智能总结"
        case .export: return "关联与导出"
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .lists: return "list.bullet"
        case .tags: return "number"
        case .model: return "cpu"
        case .summary: return "sparkles"
        case .export: return "square.and.arrow.up"
        }
    }
}
