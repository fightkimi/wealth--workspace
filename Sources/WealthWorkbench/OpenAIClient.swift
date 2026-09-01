import Foundation

enum OpenAIClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case http(Int, String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 OpenAI API Key。请到通用设置保存本机配置。"
        case .invalidEndpoint:
            return "OpenAI 访问地址无效。请填写完整 HTTPS Responses 地址；本机网关可使用 localhost 或 127.0.0.1 的 HTTP 地址。"
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
    static let defaultModel = "gpt-5.6-sol"

    static func validatedEndpoint(_ value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              let url = components.url else {
            throw OpenAIClientError.invalidEndpoint
        }
        let localHosts = ["localhost", "127.0.0.1", "::1"]
        guard scheme == "https" || (scheme == "http" && localHosts.contains(host)) else {
            throw OpenAIClientError.invalidEndpoint
        }
        return url
    }

    static func makeURLRequest(
        apiKey: String,
        endpoint: String = OpenAICredential.defaultEndpoint,
        messages: [AssistantMessage],
        model: String = defaultModel,
        stream: Bool = true
    ) throws -> URLRequest {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OpenAIClientError.missingAPIKey }

        var request = URLRequest(url: try validatedEndpoint(endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AUREL/1.1", forHTTPHeaderField: "User-Agent")

        let instructions = messages
            .filter { $0.role == "system" || $0.role == "developer" }
            .map(\.content)
            .joined(separator: "\n\n")
        let input = messages
            .filter { $0.role != "system" && $0.role != "developer" }
            .map { ["role": $0.role, "content": $0.content] }

        // Responses API keeps high-priority instructions separate from input items.
        // Source: https://developers.openai.com/api/reference/resources/responses/methods/create
        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "store": false,
            "reasoning": ["effort": "medium"],
            "text": ["verbosity": "medium"],
            "input": input
        ]
        if !instructions.isEmpty {
            body["instructions"] = instructions
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }
}

enum OpenAIStreamTextEvent: Equatable {
    case delta(String)
    case final(String)
}

enum OpenAISSEParser {
    static func contentDelta(from line: String) throws -> String? {
        guard case .delta(let value) = try textEvent(from: line) else { return nil }
        return value
    }

    static func textEvent(from line: String) throws -> OpenAIStreamTextEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: String
        if trimmed.hasPrefix("data:") {
            payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.hasPrefix("{") {
            // Some OpenAI-compatible gateways return a single JSON object even when stream=true.
            payload = trimmed
        } else {
            return nil
        }
        if payload.isEmpty || payload == "[DONE]" { return nil }
        guard let data = payload.data(using: .utf8) else { throw OpenAIClientError.invalidResponse }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenAIClientError.invalidResponse
        }
        let type = object["type"] as? String
        if ["error", "response.failed", "response.incomplete"].contains(type),
           let message = errorMessage(in: object) {
            throw OpenAIClientError.http(0, message)
        }
        if type == "response.output_text.delta", let delta = object["delta"] as? String {
            return .delta(delta)
        }
        if type == "response.output_text.done", let text = object["text"] as? String {
            return .final(text)
        }
        if type == "response.output_item.done",
           let item = object["item"] as? [String: Any],
           let text = completedText(in: item) {
            return .final(text)
        }
        if type == "response.completed",
           let response = object["response"] as? [String: Any],
           let text = completedText(in: response) {
            return .final(text)
        }
        if let choices = object["choices"] as? [[String: Any]],
           let choice = choices.first {
            if let delta = choice["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                return .delta(content)
            }
            if let message = choice["message"] as? [String: Any],
               let content = message["content"] as? String {
                return .final(content)
            }
        }
        if let text = completedText(in: object) {
            return .final(text)
        }
        return nil
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

    private static func completedText(in object: [String: Any]) -> String? {
        if let outputText = object["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        if let content = object["content"] as? [[String: Any]] {
            let text = content.compactMap { item -> String? in
                guard item["type"] as? String == "output_text" else { return nil }
                return item["text"] as? String
            }.joined()
            if !text.isEmpty { return text }
        }
        if let output = object["output"] as? [[String: Any]] {
            let text = output.compactMap(completedText).joined()
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func errorMessage(in object: [String: Any]) -> String? {
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let response = object["response"] as? [String: Any] {
            if let nested = errorMessage(in: response) { return nested }
            if let incomplete = response["incomplete_details"] as? [String: Any],
               let reason = incomplete["reason"] as? String,
               !reason.isEmpty {
                return "OpenAI 响应未完成：\(reason)"
            }
        }
        if let message = object["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}

struct OpenAIClient {
    var session: URLSession = .shared
    var model: String = OpenAIRequestBuilder.defaultModel

    func stream(apiKey: String, endpoint: String, messages: [AssistantMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try OpenAIRequestBuilder.makeURLRequest(
                        apiKey: apiKey,
                        endpoint: endpoint,
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
                    var assembled = ""
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = try OpenAISSEParser.textEvent(from: line) else { continue }
                        switch event {
                        case .delta(let delta):
                            guard !delta.isEmpty else { continue }
                            assembled += delta
                            continuation.yield(delta)
                        case .final(let finalText):
                            guard !finalText.isEmpty else { continue }
                            if assembled.isEmpty {
                                assembled = finalText
                                continuation.yield(finalText)
                            } else if finalText.hasPrefix(assembled) {
                                let suffix = String(finalText.dropFirst(assembled.count))
                                if !suffix.isEmpty {
                                    assembled = finalText
                                    continuation.yield(suffix)
                                }
                            }
                        }
                    }
                    if Task.isCancelled {
                        continuation.finish()
                    } else if assembled.isEmpty {
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
