import Foundation

/// 一条待办。纯文字；done=已完成(沉底缓冲)，pinned=置顶，completedAt=完成时刻(按条独立 4s 撤销/清扫)。
struct Todo: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var listId: String = defaultChecklistId
    var tags: [String] = []
    var done: Bool = false
    var pinned: Bool = false
    var completedAt: Date? = nil

    init(text: String, listId: String = defaultChecklistId, tags: [String] = []) {
        self.text = text
        self.listId = listId
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey { case id, text, createdAt, listId, tags, done, pinned, completedAt }
    // 宽松解码：缺/坏字段一律给默认（含 text），单条坏数据不致整盘解码失败。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
        listId = (try? c.decode(String.self, forKey: .listId)) ?? defaultChecklistId
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        done = (try? c.decode(Bool.self, forKey: .done)) ?? false
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        completedAt = try? c.decode(Date.self, forKey: .completedAt)
    }
}

struct TodoTag: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) {
        let normalized = TodoTag.normalize(name)
        self.id = id
        self.name = normalized
        self.createdAt = createdAt
    }

    static func normalize(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    }
}

/// 本地持久化：~/Library/Application Support/todo-capsule/todos.json。
enum TodoStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        // 调试/自测用独立文件，绝不写真实数据（防 logictest 等写盘自测覆盖用户待办）
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "todos.debug.json" : "todos.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [Todo] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let items = try JSONDecoder().decode([Todo].self, from: data)
            // 丢掉空 text 的坏行，但保留其余可读数据
            return items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        } catch {
            // 坏档：带时间戳备份（每次损坏各存一份、不覆盖既有备份）再返回空，绝不让随后 save 把损坏静默覆盖成永久丢失。
            let stamp = Int(Date().timeIntervalSince1970)
            let bak = fileURL.appendingPathExtension("\(stamp).bak")
            try? data.write(to: bak)
            NSLog("todo-capsule: todos.json 解码失败，已备份到 \(bak.lastPathComponent)：\(error)")
            return []
        }
    }

    static func save(_ todos: [Todo]) {
        do {
            let data = try JSONEncoder().encode(todos)
            try data.write(to: fileURL, options: .atomic)   // .atomic 防半截文件
        } catch {
            // 不再静默吞：磁盘满/无权限/沙箱拒写时至少留日志（对齐 load 的损坏上报）
            NSLog("todo-capsule: 保存失败，本次改动可能未落盘：\(error.localizedDescription)")
        }
    }
}

enum TagStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "tags.debug.json" : "tags.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [TodoTag] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TodoTag].self, from: data) else {
            return []
        }
        return normalized(decoded.map(\.name))
    }

    static func save(_ tags: [TodoTag]) {
        do {
            let data = try JSONEncoder().encode(normalized(tags.map(\.name)))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("todo-capsule: 标签保存失败：\(error.localizedDescription)")
        }
    }

    static func normalized(_ names: [String]) -> [TodoTag] {
        var seen = Set<String>()
        return names
            .map(TodoTag.normalize)
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .map { TodoTag(name: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

enum MarkdownExporter {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "todo-capsule.debug.md" : "todo-capsule.md"
        return base.appendingPathComponent(name)
    }

    static func export(lists: [Checklist], todos: [Todo], completedArchive: [Todo], collects: [CollectItem], summaries: [SummaryRecord], settings: AppSettings) {
        let markdown = render(lists: lists, todos: todos, completedArchive: completedArchive, collects: collects, summaries: summaries)
        do {
            try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            if !settings.obsidianVaultPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                syncToObsidian(markdown, settings: settings)
            }
            if settings.syncAppleNotes {
                syncToAppleNotes(markdown)
            }
        } catch {
            NSLog("todo-capsule: Markdown 导出失败：\(error.localizedDescription)")
        }
    }

    private static func render(lists: [Checklist], todos: [Todo], completedArchive: [Todo], collects: [CollectItem], summaries: [SummaryRecord]) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        var lines: [String] = [
            "# Todo Capsule",
            "",
            "_自动生成：\(df.string(from: Date()))_",
            ""
        ]

        for list in lists {
            lines.append("## \(list.name)")
            let active = todos.filter { !$0.done && $0.listId == list.id }
            if active.isEmpty {
                lines.append("- [ ] （空）")
            } else {
                for item in active {
                    lines.append("- [ ] \(escape(item.text))\(tagSuffix(item.tags))")
                }
            }
            lines.append("")
        }

        let completed = (todos.filter { $0.done } + completedArchive)
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
        lines.append("## 已完成")
        if completed.isEmpty {
            lines.append("- [x] （空）")
        } else {
            for item in completed {
                let listName = lists.first(where: { $0.id == item.listId })?.name ?? "待办"
                let date = df.string(from: item.completedAt ?? item.createdAt)
                lines.append("- [x] \(escape(item.text))\(tagSuffix(item.tags)) `\(listName)` · \(date)")
            }
        }
        lines.append("")

        lines.append("## 收藏")
        if collects.isEmpty {
            lines.append("- （空）")
        } else {
            for item in collects {
                lines.append("- \(escape(item.text))")
            }
        }
        lines.append("")

        lines.append("## 智能总结")
        if summaries.isEmpty {
            lines.append("- （空）")
        } else {
            for summary in summaries.sorted(by: { $0.createdAt > $1.createdAt }) {
                lines.append("### \(df.string(from: summary.createdAt))")
                lines.append(summary.text)
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " / ")
    }

    private static func tagSuffix(_ tags: [String]) -> String {
        guard !tags.isEmpty else { return "" }
        return " · 项目：" + tags.map { "#\($0)" }.joined(separator: " ")
    }

    private static func syncToObsidian(_ markdown: String, settings: AppSettings) {
        let raw = (settings.obsidianVaultPath as NSString).expandingTildeInPath
        let dir = URL(fileURLWithPath: raw, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try markdown.write(to: dir.appendingPathComponent("Todo Capsule.md"), atomically: true, encoding: .utf8)
        } catch {
            NSLog("todo-capsule: Obsidian 同步失败：\(error.localizedDescription)")
        }
    }

    private static func syncToAppleNotes(_ markdown: String) {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("todo-capsule-notes.md")
        try? markdown.write(to: temp, atomically: true, encoding: .utf8)
        let path = temp.path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Notes"
            set noteName to "Todo Capsule"
            set noteBody to read POSIX file "\(path)" as «class utf8»
            if not (exists folder "Todo Capsule") then make new folder with properties {name:"Todo Capsule"}
            set targetFolder to folder "Todo Capsule"
            delete notes of targetFolder whose name is noteName
            make new note at targetFolder with properties {name:noteName, body:noteBody}
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }
}

struct SummaryRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
}

enum SummaryRecordStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "summaries.debug.json" : "summaries.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [SummaryRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([SummaryRecord].self, from: data) else {
            return []
        }
        return items
    }

    static func save(_ items: [SummaryRecord]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("todo-capsule: 总结记录保存失败：\(error.localizedDescription)")
        }
    }
}
