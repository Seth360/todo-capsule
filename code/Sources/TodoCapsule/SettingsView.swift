import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var section: SettingsSection = .general
    @State private var editingModel: ModelConfig?
    @State private var editingSummary: SummaryTemplateConfig?

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
                        .font(.tc(13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                if let info = state.updateInfo {
                    Text(info.phase == .readyToRestart ? "重启后生效" : "点击查看更新")
                        .font(.tc(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
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

    @ViewBuilder
    private var headerAction: some View {
        switch section {
        case .model:
            Button {
                editingModel = ModelPreset.openAI.makeConfig()
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
            Picker("唤起窗口方式", selection: $state.settings.summonHotkeyIndex) {
                ForEach(Settings.hotkeyOptions.indices, id: \.self) { i in
                    Text(Settings.hotkeyOptions[i].name).tag(i)
                }
            }
            Picker("一键记录", selection: $state.settings.quickRecordHotkeyIndex) {
                ForEach(Settings.quickRecordHotkeyOptions.indices, id: \.self) { i in
                    Text(Settings.quickRecordHotkeyOptions[i].name).tag(i)
                }
            }
            Text("一键记录会读取当前剪贴板文本，并按行拆分写入“待办”。")
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.14)))
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(state.settings.models) { model in
                ModelCard(
                    model: model,
                    active: state.settings.activeModelId == model.id,
                    onEnable: { enableModel(model.id) },
                    onEdit: { editingModel = model },
                    onDuplicate: { duplicateModel(model) },
                    onDelete: { deleteModel(model.id) }
                )
            }
        }
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
    }

    private func duplicateModel(_ model: ModelConfig) {
        var copy = model
        copy.id = UUID().uuidString
        copy.title = "\(model.title) 副本"
        state.updateSettings { $0.models.append(copy) }
    }

    private func deleteModel(_ id: String) {
        state.updateSettings { settings in
            settings.models.removeAll { $0.id == id }
            if settings.models.isEmpty { settings.models = ModelConfig.defaults }
            if settings.activeModelId == id { settings.activeModelId = settings.models.first?.id ?? "" }
        }
    }

    private func saveModel(_ model: ModelConfig) {
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
            if let i = settings.summaryTemplates.firstIndex(where: { $0.id == template.id }) {
                settings.summaryTemplates[i] = template
            } else {
                settings.summaryTemplates.append(template)
            }
            if template.isEnabled {
                settings.activeSummaryTemplateId = template.id
                for i in settings.summaryTemplates.indices {
                    settings.summaryTemplates[i].isEnabled = settings.summaryTemplates[i].id == template.id
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

private struct ModelCard: View {
    let model: ModelConfig
    let active: Bool
    let onEnable: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary.opacity(0.65))
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.10))
                Text(model.initial).font(.tc(13, weight: .semibold)).foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.title).font(.tc(17, weight: .semibold))
                Text(model.baseURL.isEmpty ? "未配置 Base URL" : model.baseURL)
                    .font(.tc(14))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
            }
            Spacer()
            if active {
                Label("启用中", systemImage: "checkmark.circle.fill")
                    .font(.tc(13, weight: .semibold))
                    .foregroundStyle(.blue)
            } else {
                Button(action: onEnable) {
                    Label("启用", systemImage: "play")
                }
                .buttonStyle(.borderedProminent)
            }
            Button(action: onEdit) { Image(systemName: "square.and.pencil") }
            Button(action: onDuplicate) { Image(systemName: "square.on.square") }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.blue.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.blue.opacity(0.75) : Color.secondary.opacity(0.22), lineWidth: active ? 1.5 : 1))
    }
}

private struct SummaryTemplateCard: View {
    let template: SummaryTemplateConfig
    let listNames: String
    let active: Bool
    let onEnable: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: active ? "sparkles" : "doc.text")
                .foregroundStyle(active ? .blue : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(template.title).font(.tc(17, weight: .semibold))
                Text("\(template.period.title) · \(listNames)")
                    .font(.tc(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(active ? "启用中" : "启用", action: onEnable)
                .disabled(active)
            Button(action: onEdit) { Image(systemName: "square.and.pencil") }
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.blue.opacity(0.08) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? Color.blue.opacity(0.75) : Color.secondary.opacity(0.22), lineWidth: active ? 1.5 : 1))
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
        let preset = ModelPreset.matching(initial) ?? .custom
        let currentModelName = initial.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        _model = State(initialValue: initial)
        _selectedPresetId = State(initialValue: preset.id)
        _availableModelNames = State(initialValue: currentModelName.isEmpty ? [] : [currentModelName])
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("模型配置").font(.tc(22, weight: .semibold))
            Form {
                TextField("标题", text: $model.title)
                Picker("常用模型", selection: presetSelection) {
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
                    if saved.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        title: "DeepSeek · deepseek-chat",
        providerName: "DeepSeek",
        baseURL: "https://api.deepseek.com",
        modelName: "deepseek-chat",
        supportsRouting: true
    )

    static let qwen = ModelPreset(
        id: "qwen",
        title: "通义 · qwen-plus",
        providerName: "通义千问",
        baseURL: "https://dashscope.aliyuncs.com/compatible-mode",
        modelName: "qwen-plus",
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

    static let all: [ModelPreset] = [.openAI, .deepSeek, .qwen, .custom]

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
                    TextEditor(text: $template.prompt)
                        .font(.tc(12))
                        .frame(height: 180)
                    Text("使用 {{content}} 作为待办内容占位符。")
                        .font(.tc(11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
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
