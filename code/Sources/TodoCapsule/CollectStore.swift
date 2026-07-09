import Foundation

/// 一条收藏。和待办是两套并行逻辑：收藏不参与"完成/沉底/清扫"，只为「写进去、随时取」。
/// sensitive=敏感项(密码/账号)，UI 打码显示——注意这是防窥视，不是加密：collect.json 仍是明文本地存储。
struct CollectItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var sensitive: Bool = false
    var pinned: Bool = false
    var createdAt: Date = Date()

    init(text: String, sensitive: Bool = false, pinned: Bool = false) {
        self.text = text
        self.sensitive = sensitive
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey { case id, text, sensitive, pinned, createdAt }
    // 宽松解码：缺/坏字段一律给默认，单条坏数据不致整盘解码失败（对齐 Todo）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        sensitive = (try? c.decode(Bool.self, forKey: .sensitive)) ?? false
        pinned = (try? c.decode(Bool.self, forKey: .pinned)) ?? false
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }
}

/// 收藏夹本地持久化：~/Library/Application Support/todo-capsule/collect.json（与 todos.json 分文件）。
/// 轻量优先：和待办同一套明文 JSON + 原子写 + 坏档备份，不上加密（用户明确要 5 个横评的轻体感）。
enum CollectStore {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("todo-capsule", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let name = ProcessInfo.processInfo.environment["TC_DEBUG_MODE"] != nil ? "collect.debug.json" : "collect.json"
        return base.appendingPathComponent(name)
    }

    static func load() -> [CollectItem] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            let items = try JSONDecoder().decode([CollectItem].self, from: data)
            return items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        } catch {
            // 坏档：带时间戳备份再返回空，绝不让随后 save 把损坏静默覆盖成永久丢失（对齐 TodoStore）。
            let stamp = Int(Date().timeIntervalSince1970)
            let bak = fileURL.appendingPathExtension("\(stamp).bak")
            try? data.write(to: bak)
            NSLog("todo-capsule: collect.json 解码失败，已备份到 \(bak.lastPathComponent)：\(error)")
            return []
        }
    }

    static func save(_ items: [CollectItem]) {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: fileURL, options: .atomic)   // .atomic 防半截文件
        } catch {
            NSLog("todo-capsule: 收藏保存失败，本次改动可能未落盘：\(error.localizedDescription)")
        }
    }
}
