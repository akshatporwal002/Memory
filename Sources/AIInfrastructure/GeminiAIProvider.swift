import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GeminiAIProvider: AIProvider {
    public let id = "gemini"
    public init() {}
    public func models(token: String) async throws -> [AIModelDescriptor] {
        let session = URLSession(configuration: .ephemeral, delegate: GeminiRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var models: [AIModelDescriptor] = [], page: String?, seenPages = Set<String>()
        for _ in 0..<20 {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "1000")]
            if let page { components.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
            var request = URLRequest(url: components.url!); request.timeoutInterval = 30
            request.setValue(token, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIProviderError.unavailable }
            models += try Self.decodeModels(root)
            guard let next = root["nextPageToken"] as? String, !next.isEmpty else {
                var seen = Set<String>(); return models.filter { seen.insert($0.id).inserted }
            }
            guard next.utf8.count <= 8000, seenPages.insert(next).inserted else { throw AIProviderError.exceededLimit }
            page = next
        }
        throw AIProviderError.exceededLimit
    }
    static func decodeModels(_ root: [String: Any]) throws -> [AIModelDescriptor] {
        guard let models = root["models"] as? [[String: Any]] else { throw AIProviderError.unavailable }
        return models.compactMap { entry in
            guard let name = entry["name"] as? String, name.hasPrefix("models/"),
                  let methods = entry["supportedGenerationMethods"] as? [String], methods.contains("generateContent") else { return nil }
            let model = String(name.dropFirst(7))
            guard validModel(model) else { return nil }
            return AIModelDescriptor(provider: "gemini", model: model, supportsTools: false,
                displayName: entry["displayName"] as? String, toolSupportKnown: false)
        }
    }
    private static func validModel(_ model: String) -> Bool {
        !model.isEmpty && model.utf8.count <= 200 && model.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }
    public func resolveTools(_ model: AIModelDescriptor, token: String) async throws -> AIModelDescriptor {
        guard model.provider == id else { throw AIProviderError.unsupportedModel }
        guard model.toolSupportKnown == false else { return model }
        var checked = model; checked.supportsTools = true
        let probe = AIToolDefinition(name: "capability_check", summary: "No application action; capability check only.", parametersJSON: #"{"type":"object","properties":{},"additionalProperties":false}"#)
        do { _ = try await respond(AIRequest(model: checked, instructions: "Reply Ready without calling tools.", input: [.message(AIMessage(role: "user", text: "Ready?"))], tools: [probe], outputLimit: 2000), token: token) }
        catch AIProviderError.unsupportedModel { checked.supportsTools = false }
        checked.toolSupportKnown = true; return checked
    }
    public func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = URLSession(configuration: .ephemeral, delegate: GeminiRedirectBlocker(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    guard request.model.provider == id, Self.validModel(request.model.model), request.tools.isEmpty || request.model.supportsTools else { throw AIProviderError.unsupportedModel }
                    let body = try GeminiWire.request(request)
                    var http = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(request.model.model):streamGenerateContent?alt=sse")!)
                    http.httpMethod = "POST"; http.timeoutInterval = 90
                    http.setValue(token, forHTTPHeaderField: "x-goog-api-key")
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.httpBody = try JSONSerialization.data(withJSONObject: body)
                    var decoder = GeminiStreamDecoder(limit: request.outputLimit)
                    #if !os(Windows)
                    let (bytes, response) = try await session.bytes(for: http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        var failure = Data(); for try await byte in bytes { guard failure.count < 8000 else { break }; failure.append(byte) }
                        throw Self.failure(failure)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try decoder.accept(line) { continuation.yield(event) }
                        if decoder.completed { break }
                    }
                    #else
                    let (data, response) = try await session.data(for: http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Self.failure(Data(data.prefix(8000))) }
                    guard data.count <= 2_000_000 else { throw AIProviderError.exceededLimit }
                    for line in String(decoding: data, as: UTF8.self).components(separatedBy: "\n") {
                        for event in try decoder.accept(line) { continuation.yield(event) }
                    }
                    #endif
                    guard decoder.completed else { throw AIProviderError.incomplete }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
    private static func failure(_ data: Data) -> AIProviderError {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return .unavailable }
        let message = (error["message"] as? String ?? "").lowercased()
        if message.contains("function") || message.contains("tool") {
            if message.contains("not supported") || message.contains("does not support") { return .unsupportedModel }
        }
        return .unavailable
    }
}

enum GeminiWire {
    static func validateContext(_ value: [String: Any]) throws {
        guard let content = value["content"] as? [String: Any], content["role"] as? String == "model",
              let parts = content["parts"] as? [[String: Any]], !parts.isEmpty, parts.count <= 1000,
              let calls = value["calls"] as? [[String: String]], calls.count <= 12,
              calls.allSatisfy({ !($0["id"] ?? "").isEmpty && !($0["name"] ?? "").isEmpty }) else { throw AIProviderError.invalidTool }
        guard parts.allSatisfy({ Set($0.keys).isSubset(of: ["text", "thought", "thoughtSignature", "functionCall"]) }) else { throw AIProviderError.invalidTool }
        let functions = parts.compactMap { $0["functionCall"] as? [String: Any] }
        guard functions.count == calls.count, Set(calls.compactMap { $0["id"] }).count == calls.count else { throw AIProviderError.invalidTool }
        for (function, call) in zip(functions, calls) {
            guard let name = function["name"] as? String, name == call["name"],
                  let args = (function["args"] ?? [:]) as? [String: Any],
                  try JSONSerialization.data(withJSONObject: args).count <= 30_000,
                  function["id"] == nil || function["id"] as? String == call["id"] else { throw AIProviderError.invalidTool }
        }
    }
    static func request(_ request: AIRequest) throws -> [String: Any] {
        var contents: [[String: Any]] = [], calls: [String: AIToolCall] = [:], opaqueCallIDs = Set<String>(), serverCallIDs = Set<String>()
        for item in request.input {
            if case .call(let call) = item {
                guard calls[call.id] == nil else { throw AIProviderError.invalidTool }
                calls[call.id] = call
            }
            if case .context(let context) = item {
                guard context.provider == "gemini", context.json.utf8.count <= 350_000,
                      let value = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as? [String: Any] else { throw AIProviderError.invalidTool }
                try validateContext(value)
                for call in value["calls"] as? [[String: String]] ?? [] {
                    guard opaqueCallIDs.insert(call["id"]!).inserted else { throw AIProviderError.invalidTool }
                }
                let content = value["content"] as! [String: Any]
                for part in content["parts"] as! [[String: Any]] {
                    if let id = (part["functionCall"] as? [String: Any])?["id"] as? String { serverCallIDs.insert(id) }
                }
            }
        }
        for item in request.input {
            if case .context(let context) = item {
                let value = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as! [String: Any]
                let content = value["content"] as! [String: Any]
                let functions = (content["parts"] as! [[String: Any]]).compactMap { $0["functionCall"] as? [String: Any] }
                for (function, metadata) in zip(functions, value["calls"] as! [[String: String]]) {
                    guard let call = calls[metadata["id"]!], call.name == metadata["name"],
                          let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any],
                          NSDictionary(dictionary: args).isEqual(to: (function["args"] ?? [:]) as! [String: Any]) else { throw AIProviderError.invalidTool }
                }
            }
        }
        var previousOpaque = false
        for item in request.input {
            switch item {
            case .message(let message):
                guard ["user", "assistant"].contains(message.role) else { throw AIProviderError.invalidTool }
                if previousOpaque && message.role == "assistant" { previousOpaque = false; continue }
                contents.append(["role": message.role == "assistant" ? "model" : "user", "parts": [["text": message.text]]])
                previousOpaque = false
            case .context(let context):
                let value = try JSONSerialization.jsonObject(with: Data(context.json.utf8)) as! [String: Any]
                if contents.last?["role"] as? String == "model", !previousOpaque { contents.removeLast() }
                contents.append(value["content"] as! [String: Any]); previousOpaque = true
            case .call(let call):
                if !opaqueCallIDs.contains(call.id) {
                    guard let args = try JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: Any] else { throw AIProviderError.invalidTool }
                    contents.append(["role": "model", "parts": [["functionCall": ["name": call.name, "id": call.id, "args": args]]]])
                }
            case .result(let id, let output):
                guard let call = calls[id], output.utf8.count <= 150_000 else { throw AIProviderError.invalidTool }
                var result: [String: Any] = ["name": call.name, "response": ["output": output]]
                // Locally generated call IDs are journal keys, not invented server IDs.
                if !opaqueCallIDs.contains(id) || serverCallIDs.contains(id) { result["id"] = id }
                let part: [String: Any] = ["functionResponse": result]
                if contents.last?["role"] as? String == "user", let existing = contents.last?["parts"] as? [[String: Any]], existing.first?["functionResponse"] != nil {
                    contents[contents.count - 1]["parts"] = existing + [part]
                } else { contents.append(["role": "user", "parts": [part]]) }
                previousOpaque = false
            }
        }
        var body: [String: Any] = ["contents": contents, "systemInstruction": ["parts": [["text": request.instructions]]], "generationConfig": ["candidateCount": 1]]
        if !request.tools.isEmpty {
            body["tools"] = [["functionDeclarations": try request.tools.map { tool -> [String: Any] in
                guard let schema = try JSONSerialization.jsonObject(with: Data(tool.parametersJSON.utf8)) as? [String: Any], schema["type"] as? String == "object" else { throw AIProviderError.invalidTool }
                return ["name": tool.name, "description": tool.summary, "parametersJsonSchema": schema]
            }]]
        }
        return body
    }
}

public struct GeminiStreamDecoder {
    public private(set) var completed = false
    private let limit: Int
    private var wireSize = 0, textSize = 0
    private var parts: [[String: Any]] = [], calls: [AIToolCall] = []
    public init(limit: Int = 150_000) { self.limit = limit }
    public mutating func accept(_ line: String) throws -> [AIEvent] {
        guard !completed, line.hasPrefix("data:") else { return [] }
        let data = Data(line.dropFirst(5).trimmingCharacters(in: .whitespaces).utf8)
        wireSize += data.count
        guard wireSize <= max(limit * 12, 1_000_000) else { throw AIProviderError.exceededLimit }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil,
              let candidates = root["candidates"] as? [[String: Any]], candidates.count == 1 else { throw AIProviderError.incomplete }
        let candidate = candidates[0]
        var events: [AIEvent] = []
        if let raw = root["usageMetadata"] as? [String: Any], let usage = AIUsage.gemini(raw) { events.append(.usage(usage)) }
        if let content = candidate["content"] as? [String: Any], let next = content["parts"] as? [[String: Any]] {
            for part in next {
                guard Set(part.keys).isSubset(of: ["text", "thought", "thoughtSignature", "functionCall"]) else { throw AIProviderError.incomplete }
                parts.append(part)
                guard parts.count <= 1000 else { throw AIProviderError.exceededLimit }
                if let text = part["text"] as? String, part["thought"] as? Bool != true {
                    textSize += text.utf8.count; guard textSize <= limit else { throw AIProviderError.exceededLimit }
                    events.append(.textDelta(text))
                }
                if let function = part["functionCall"] as? [String: Any] {
                    guard let name = function["name"] as? String, !name.isEmpty, name.utf8.count <= 128,
                          let args = (function["args"] ?? [:]) as? [String: Any], calls.count < 12 else { throw AIProviderError.invalidTool }
                    let encoded = try JSONSerialization.data(withJSONObject: args, options: .sortedKeys)
                    guard encoded.count <= 30_000 else { throw AIProviderError.invalidTool }
                    let id = function["id"] as? String ?? "gemini-local-" + UUID().uuidString
                    guard !id.isEmpty, !calls.contains(where: { $0.id == id }) else { throw AIProviderError.invalidTool }
                    calls.append(AIToolCall(id: id, name: name, arguments: String(decoding: encoded, as: UTF8.self)))
                }
            }
        }
        if let reason = candidate["finishReason"] as? String {
            guard reason == "STOP", !parts.isEmpty else { throw AIProviderError.incomplete }
            let payload: [String: Any] = ["content": ["role": "model", "parts": parts], "calls": calls.map { ["id": $0.id, "name": $0.name] }]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            events.append(.contextItem(try AIContextItem(provider: "gemini", json: json)))
            events += calls.map { .toolCall($0) }; completed = true; events.append(.completed)
        }
        return events
    }
}
private final class GeminiRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
