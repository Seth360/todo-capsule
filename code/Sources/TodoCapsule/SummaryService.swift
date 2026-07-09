import Foundation

enum SummaryServiceError: LocalizedError {
    case missingConfiguration
    case badURL
    case emptyResponse
    case modelNotFound(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "请先在设置里配置模型 Base URL 和 API Key"
        case .badURL:
            return "模型 API 地址无效"
        case .emptyResponse:
            return "模型没有返回总结内容"
        case .modelNotFound(let model):
            return "模型不存在：\(model)。请在设置里点击“自动获取模型”，选择可用模型后保存"
        case .http(let code, let body):
            return "模型请求失败（\(code)）：\(body.prefix(120))"
        }
    }
}

enum SummaryService {
    static func summarize(settings: AppSettings, prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        let config = settings.activeModel
        let base = (config?.baseURL ?? settings.modelBaseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (config?.apiKey ?? settings.modelAPIKey).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = effectiveModelName(config: config, fallback: settings.modelName)
        guard !base.isEmpty, !key.isEmpty, !model.isEmpty else {
            completion(.failure(SummaryServiceError.missingConfiguration))
            return
        }
        guard let url = endpointURL(from: base) else {
            completion(.failure(SummaryServiceError.badURL))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        for (name, value) in parseHeaders(config?.customHeaders ?? settings.modelCustomHeaders) {
            req.setValue(value, forHTTPHeaderField: name)
        }
        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: "你是一个简洁、诚实、善于归纳行动项的待办总结助手。"),
                ChatMessage(role: "user", content: prompt)
            ],
            temperature: 0.3
        )
        req.httpBody = try? JSONEncoder().encode(body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let raw = String(data: data ?? Data(), encoding: .utf8) ?? ""
            guard (200..<300).contains(status) else {
                if raw.contains("model_not_found") {
                    completion(.failure(SummaryServiceError.modelNotFound(model)))
                    return
                }
                completion(.failure(SummaryServiceError.http(status, raw)))
                return
            }
            if let data, let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
               let text = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                completion(.success(text))
            } else {
                completion(.failure(SummaryServiceError.emptyResponse))
            }
        }.resume()
    }

    private static func effectiveModelName(config: ModelConfig?, fallback: String) -> String {
        let explicit = (config?.modelName ?? fallback).trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let hints = [
            config?.providerName,
            config?.title,
            config?.baseURL
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if hints.contains("deepseek") { return "deepseek-chat" }
        if hints.contains("dashscope") || hints.contains("aliyun") || hints.contains("qwen") || hints.contains("通义") {
            return "qwen-plus"
        }
        return "gpt-4.1"
    }

    private static func endpointURL(from base: String) -> URL? {
        if base.contains("/chat/completions") {
            return URL(string: base)
        }
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        if trimmed.hasSuffix("/v1") {
            return URL(string: "\(trimmed)/chat/completions")
        }
        return URL(string: "\(trimmed)/v1/chat/completions")
    }

    private static func parseHeaders(_ raw: String) -> [(String, String)] {
        raw.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
            return (parts[0], parts[1])
        }
    }
}

enum ModelListService {
    static func fetch(baseURL: String, apiKey: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !key.isEmpty else {
            completion(.failure(SummaryServiceError.missingConfiguration))
            return
        }
        guard let url = endpointURL(from: base) else {
            completion(.failure(SummaryServiceError.badURL))
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            let raw = String(data: data ?? Data(), encoding: .utf8) ?? ""
            guard (200..<300).contains(status) else {
                completion(.failure(SummaryServiceError.http(status, raw)))
                return
            }
            guard let data,
                  let decoded = try? JSONDecoder().decode(ModelListResponse.self, from: data) else {
                completion(.failure(SummaryServiceError.emptyResponse))
                return
            }
            let names = decoded.data
                .map(\.id)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .removingDuplicates()
            completion(names.isEmpty ? .failure(SummaryServiceError.emptyResponse) : .success(names))
        }.resume()
    }

    private static func endpointURL(from base: String) -> URL? {
        let withoutChat = base.replacingOccurrences(of: "/chat/completions", with: "")
        let trimmed = withoutChat.hasSuffix("/") ? String(withoutChat.dropLast()) : withoutChat
        if trimmed.hasSuffix("/v1") {
            return URL(string: "\(trimmed)/models")
        }
        return URL(string: "\(trimmed)/v1/models")
    }
}

private struct ModelListResponse: Codable {
    let data: [ModelListItem]
}

private struct ModelListItem: Codable {
    let id: String
}

private extension Array where Element == String {
    func removingDuplicates() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

private struct ChatRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: ChatMessage
    }
}
