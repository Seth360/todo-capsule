import Foundation

let defaultChecklistId = "todo"

struct Checklist: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    static let todo = Checklist(id: defaultChecklistId, name: "待办", createdAt: Date(timeIntervalSince1970: 0))
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case chinese, english
    var id: String { rawValue }
    var title: String { self == .chinese ? "中文" : "英文" }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        case .system: return "跟随系统"
        }
    }
}

enum CapsulePosition: String, Codable, CaseIterable, Identifiable {
    case right, left
    var id: String { rawValue }
    var title: String { self == .right ? "最右侧" : "最左侧" }
}

enum SummaryPeriod: String, Codable, CaseIterable, Identifiable {
    case today, week, month, quarter, halfYear, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "本日"
        case .week: return "本周"
        case .month: return "本月"
        case .quarter: return "季度"
        case .halfYear: return "半年"
        case .year: return "一年"
        }
    }
}

struct ModelConfig: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var providerName: String
    var baseURL: String
    var apiKey: String
    var modelName: String
    var customHeaders: String = ""
    var supportsRouting: Bool = true

    var initial: String {
        let words = title.split(separator: " ").prefix(2)
        let value = words.map { String($0.prefix(1)) }.joined()
        return value.isEmpty ? "AI" : value.uppercased()
    }

    static let defaults: [ModelConfig] = [
        ModelConfig(id: "openai-official", title: "OpenAI Official", providerName: "OpenAI", baseURL: "https://api.openai.com", apiKey: "", modelName: "gpt-4.1", supportsRouting: false),
        ModelConfig(id: "deepseek", title: "DeepSeek", providerName: "DeepSeek", baseURL: "https://api.deepseek.com", apiKey: "", modelName: "deepseek-chat"),
        ModelConfig(id: "qwen", title: "通义千问", providerName: "通义千问", baseURL: "https://dashscope.aliyuncs.com/compatible-mode", apiKey: "", modelName: "qwen-plus"),
        ModelConfig(id: "custom", title: "自定义 API", providerName: "Custom", baseURL: "", apiKey: "", modelName: "")
    ]
}

struct SummaryTemplateConfig: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var period: SummaryPeriod
    var listIds: [String]
    var includeCollects: Bool
    var prompt: String
    var isEnabled: Bool = false

    static let week = SummaryTemplateConfig(
        id: "weekly-summary",
        title: "周总结",
        period: .week,
        listIds: [defaultChecklistId],
        includeCollects: false,
        prompt: """
        请根据以下待办内容，生成一份简洁的周总结。请按「本周完成」「进行中」「风险与阻塞」「下周建议」四段输出。

        {{content}}
        """,
        isEnabled: true
    )

    static let halfYear = SummaryTemplateConfig(
        id: "half-year-summary",
        title: "半年总结",
        period: .halfYear,
        listIds: [defaultChecklistId],
        includeCollects: true,
        prompt: """
        请根据以下待办、收藏和完成记录，生成一份半年复盘。请包含「关键成果」「长期推进事项」「沉淀的方法」「下阶段重点」。

        {{content}}
        """,
        isEnabled: false
    )
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    var language: AppLanguage = .chinese
    var theme: AppTheme = .dark
    var position: CapsulePosition = .right

    var summonHotkeyIndex: Int = 0
    var quickRecordHotkeyIndex: Int = 0
    var summonHotkey: HotkeyOption?
    var quickRecordHotkey: HotkeyOption?

    var modelProviderName: String = "OpenAI Compatible"
    var modelBaseURL: String = ""
    var modelAPIKey: String = ""
    var modelName: String = ""
    var modelCustomHeaders: String = ""
    var models: [ModelConfig] = ModelConfig.defaults
    var activeModelId: String = "openai-official"

    var summaryTemplate: String = """
    请根据以下待办内容，生成一份简洁的周总结。请按「本周完成」「进行中」「风险与阻塞」「下周建议」四段输出。

    {{content}}
    """
    var summaryPeriod: SummaryPeriod = .week
    var summaryListIds: [String] = [defaultChecklistId]
    var summaryIncludeCollects: Bool = false
    var summaryTemplates: [SummaryTemplateConfig] = [.week, .halfYear]
    var activeSummaryTemplateId: String = "weekly-summary"

    var obsidianVaultPath: String = ""
    var syncAppleNotes: Bool = false

    mutating func normalize() {
        summonHotkeyIndex = normalizedIndex(summonHotkeyIndex, count: Settings.hotkeyOptions.count)
        quickRecordHotkeyIndex = normalizedIndex(quickRecordHotkeyIndex, count: Settings.quickRecordHotkeyOptions.count)
        if summonHotkey == nil {
            summonHotkey = Settings.hotkeyOptions[summonHotkeyIndex]
        }
        if quickRecordHotkey == nil {
            quickRecordHotkey = Settings.quickRecordHotkeyOptions[quickRecordHotkeyIndex]
        }
        if models.isEmpty {
            if modelBaseURL.isEmpty && modelAPIKey.isEmpty && modelName.isEmpty {
                models = ModelConfig.defaults
            } else {
                models = [ModelConfig(title: modelProviderName, providerName: modelProviderName, baseURL: modelBaseURL, apiKey: modelAPIKey, modelName: modelName, customHeaders: modelCustomHeaders)]
            }
        }
        if !models.contains(where: { $0.id == activeModelId }) {
            activeModelId = models.first?.id ?? "openai-official"
        }
        if summaryTemplates.isEmpty {
            var migrated = SummaryTemplateConfig.week
            migrated.period = summaryPeriod
            migrated.listIds = summaryListIds
            migrated.includeCollects = summaryIncludeCollects
            migrated.prompt = summaryTemplate
            migrated.isEnabled = true
            summaryTemplates = [migrated, .halfYear]
        }
        if !summaryTemplates.contains(where: { $0.id == activeSummaryTemplateId }) {
            activeSummaryTemplateId = summaryTemplates.first?.id ?? "weekly-summary"
        }
    }

    var activeModel: ModelConfig? {
        models.first(where: { $0.id == activeModelId }) ?? models.first
    }

    var activeSummaryTemplate: SummaryTemplateConfig {
        summaryTemplates.first(where: { $0.id == activeSummaryTemplateId }) ?? SummaryTemplateConfig.week
    }

    private func normalizedIndex(_ value: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, value), count - 1)
    }
}

enum AppSettingsStore {
    private static let key = "todoCapsule.appSettings.v1"

    static func load() -> AppSettings {
        var settings: AppSettings
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            settings = AppSettings()
            settings.normalize()
            return settings
        }
        settings = decoded
        settings.normalize()
        return settings
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

enum ChecklistStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "lists.debug.json" : "lists.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [Checklist] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Checklist].self, from: data) else {
            return [.todo]
        }
        var lists = decoded.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !lists.contains(where: { $0.id == defaultChecklistId }) {
            lists.insert(.todo, at: 0)
        }
        lists.sort { lhs, rhs in
            if lhs.id == defaultChecklistId { return true }
            if rhs.id == defaultChecklistId { return false }
            return lhs.createdAt < rhs.createdAt
        }
        return lists
    }

    static func save(_ lists: [Checklist]) {
        var normalized = lists
        if !normalized.contains(where: { $0.id == defaultChecklistId }) {
            normalized.insert(.todo, at: 0)
        }
        do {
            let data = try JSONEncoder().encode(normalized)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("todo-capsule: 清单保存失败：\(error.localizedDescription)")
        }
    }
}

enum CompletedTodoStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "completed.debug.json" : "completed.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [Todo] {
        guard let data = try? Data(contentsOf: fileURL),
              let todos = try? JSONDecoder().decode([Todo].self, from: data) else {
            return []
        }
        return todos.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func save(_ todos: [Todo]) {
        do {
            let data = try JSONEncoder().encode(todos)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("todo-capsule: 已完成清单保存失败：\(error.localizedDescription)")
        }
    }
}
