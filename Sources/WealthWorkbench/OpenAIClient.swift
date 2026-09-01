import Foundation

enum OpenAIClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case http(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 OpenAI API Key。请到通用设置保存到本地文件，或设置环境变量 OPENAI_API_KEY。"
        case .invalidResponse:
            return "OpenAI 返回了无法识别的内容"
        case .http(let code, let body):
            let detail = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "OpenAI HTTP \(code)" : "OpenAI HTTP \(code)：\(detail)"
        case .emptyOutput:
            return "OpenAI 没有返回有效回复"
        }
    }
}

enum OpenAIRequestBuilder {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    static let defaultModel = "gpt-5.6-sol"

    static func makeURLRequest(
        apiKey: String,
        messages: [AssistantMessage],
        model: String = defaultModel,
        stream: Bool = true
    ) throws -> URLRequest {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIClientError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AUREL/1.1", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "model": model,
            "stream": stream,
            "store": false,
            "reasoning": ["effort": "medium"],
            "text": ["verbosity": "medium"],
            "input": messages.map { ["role": $0.role, "content": $0.content] }
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}

enum OpenAISSEParser {
    private struct StreamEvent: Decodable {
        struct APIError: Decodable { var message: String? }

        var type: String?
        var delta: String?
        var error: APIError?
    }

    static func contentDelta(from line: String) throws -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload.isEmpty || payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8) else { throw OpenAIClientError.invalidResponse }
        let event = try JSONDecoder().decode(StreamEvent.self, from: data)
        if let message = event.error?.message, !message.isEmpty {
            throw OpenAIClientError.http(0, message)
        }
        guard event.type == "response.output_text.delta" else { return nil }
        return event.delta
    }

    static func errorMessage(from data: Data, status: Int) -> OpenAIClientError {
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

struct OpenAIClient {
    var session: URLSession = .shared
    var model: String = OpenAIRequestBuilder.defaultModel

    func stream(apiKey: String, messages: [AssistantMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try OpenAIRequestBuilder.makeURLRequest(
                        apiKey: apiKey,
                        messages: messages,
                        model: model,
                        stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAIClientError.invalidResponse
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var collected = Data()
                        for try await chunk in bytes {
                            collected.append(chunk)
                        }
                        throw OpenAISSEParser.errorMessage(from: collected, status: http.statusCode)
                    }
                    var produced = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let delta = try OpenAISSEParser.contentDelta(from: line), !delta.isEmpty {
                            produced = true
                            continuation.yield(delta)
                        }
                    }
                    if Task.isCancelled {
                        continuation.finish()
                    } else if !produced {
                        continuation.finish(throwing: OpenAIClientError.emptyOutput)
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
