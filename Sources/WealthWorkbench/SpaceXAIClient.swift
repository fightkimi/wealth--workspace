import Foundation

struct AssistantMessage: Equatable {
    var role: String
    var content: String
}

typealias SpaceXAIMessage = AssistantMessage

enum SpaceXAIClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 SpaceXAI API Key。请到通用设置保存到本地文件，或设置环境变量 XAI_API_KEY。"
        case .invalidResponse:
            return "SpaceXAI 返回了无法识别的内容"
        case .http(let code, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "SpaceXAI HTTP \(code)" : "SpaceXAI HTTP \(code)：\(detail)"
        case .emptyOutput:
            return "SpaceXAI 没有返回有效回复"
        }
    }
}

enum SpaceXAIRequestBuilder {
    static let endpoint = URL(string: "https://api.x.ai/v1/chat/completions")!
    static let defaultModel = "grok-4.6"

    static func makeURLRequest(
        apiKey: String,
        messages: [AssistantMessage],
        model: String = defaultModel,
        stream: Bool = true
    ) throws -> URLRequest {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SpaceXAIClientError.missingAPIKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("WealthWorkbench/1.1", forHTTPHeaderField: "User-Agent")
        let body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}

enum SpaceXAISSEParser {
    struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { var content: String? }
            var delta: Delta?
            var finish_reason: String?
        }

        struct APIError: Decodable { var message: String? }

        var choices: [Choice]?
        var error: APIError?
    }

    static func contentDelta(from line: String) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.isEmpty || payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8) else { throw SpaceXAIClientError.invalidResponse }
        let chunk = try JSONDecoder().decode(StreamChunk.self, from: data)
        if let message = chunk.error?.message, !message.isEmpty {
            throw SpaceXAIClientError.http(0, message)
        }
        return chunk.choices?.first?.delta?.content
    }

    static func errorMessage(from data: Data, status: Int) -> SpaceXAIClientError {
        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
           let message = chunk.error?.message,
           !message.isEmpty {
            return .http(status, message)
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return .http(status, message)
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .http(status, raw)
    }
}

struct SpaceXAIClient {
    var session: URLSession = .shared
    var model: String = SpaceXAIRequestBuilder.defaultModel

    func stream(apiKey: String, messages: [AssistantMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try SpaceXAIRequestBuilder.makeURLRequest(
                        apiKey: apiKey,
                        messages: messages,
                        model: model,
                        stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw SpaceXAIClientError.invalidResponse
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var collected = Data()
                        for try await chunk in bytes {
                            collected.append(chunk)
                        }
                        throw SpaceXAISSEParser.errorMessage(from: collected, status: http.statusCode)
                    }
                    var produced = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let delta = try SpaceXAISSEParser.contentDelta(from: line), !delta.isEmpty {
                            produced = true
                            continuation.yield(delta)
                        }
                    }
                    if Task.isCancelled {
                        continuation.finish()
                    } else if !produced {
                        continuation.finish(throwing: SpaceXAIClientError.emptyOutput)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
