import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AIModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { provider + ":" + model }
    public var provider: String
    public var model: String
    public var supportsTools: Bool
    public init(provider: String, model: String, supportsTools: Bool) {
        self.provider = provider; self.model = model; self.supportsTools = supportsTools
    }
}
public struct AIMessage: Codable, Equatable, Sendable {
    public var role: String
    public var text: String
    public var modelID: String?
    public init(role: String, text: String, modelID: String? = nil) { self.role = role; self.text = text; self.modelID = modelID }
}
public struct AIToolCall: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var arguments: String
    public init(id: String, name: String, arguments: String) { self.id = id; self.name = name; self.arguments = arguments }
}
public enum AIInput: Codable, Equatable, Sendable {
    case message(AIMessage), call(AIToolCall), result(callID: String, output: String)
    var wire: [String: Any] {
        switch self {
        case .message(let message): return ["role":message.role,"content":message.text]
        case .call(let call): return ["type":"function_call","call_id":call.id,"name":call.name,"arguments":call.arguments]
        case .result(let id,let output): return ["type":"function_call_output","call_id":id,"output":output]
        }
    }
}
public struct AIToolDefinition: Codable, Equatable, Sendable {
    public let name: String
    public let summary: String
    public let parametersJSON: String
    public init(name: String, summary: String, parametersJSON: String) { self.name = name; self.summary = summary; self.parametersJSON = parametersJSON }
    var wire: [String: Any] {
        ["type":"function","name":name,"description":summary,
         "parameters":(try? JSONSerialization.jsonObject(with: Data(parametersJSON.utf8))) ?? [:]]
    }
}
public struct AIRequest: Sendable {
    public var model: AIModelDescriptor
    public var instructions: String
    public var input: [AIInput]
    public var tools: [AIToolDefinition]
    public var outputLimit: Int
    public init(model: AIModelDescriptor, instructions: String, input: [AIInput], tools: [AIToolDefinition] = [], outputLimit: Int = 150_000) {
        self.model = model; self.instructions = instructions; self.input = input; self.tools = tools; self.outputLimit = outputLimit
    }
}
public enum AIEvent: Sendable, Equatable { case textDelta(String), toolCall(AIToolCall), completed }
public struct AIResponse: Sendable {
    public var text = ""
    public var calls: [AIToolCall] = []
    public init() {}
}
public struct AIConversation: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var model: AIModelDescriptor?
    public var messages: [AIMessage]
    public var input: [AIInput]
    public init(id: String, model: AIModelDescriptor? = nil) { self.id = id; self.model = model; messages = []; input = [] }
}
public enum AIProviderError: Error, LocalizedError, Equatable {
    case unavailable, incomplete, exceededLimit, invalidTool, unsupportedModel
    public var errorDescription: String? {
        switch self {
        case .unavailable: "AI unavailable. Check your account, model access and usage limits."
        case .incomplete: "AI stopped before completion. Your saved work is unchanged."
        case .exceededLimit: "The AI output exceeded its limit. Try a smaller request."
        case .invalidTool: "The AI returned an invalid action. No such action was executed."
        case .unsupportedModel: "This model does not support app actions. Choose a tool-capable model."
        }
    }
}
public protocol AIProvider: Sendable {
    var id: String { get }
    func models(token: String) async throws -> [AIModelDescriptor]
    func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error>
}
public extension AIProvider {
    func respond(_ request: AIRequest, token: String) async throws -> AIResponse {
        var result = AIResponse(), completed = false
        for try await event in stream(request, token: token) {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let text): result.text += text
            case .toolCall(let call):
                guard !result.calls.contains(where: { $0.id == call.id }) else { continue }
                result.calls.append(call)
            case .completed: completed = true
            }
        }
        guard completed else { throw AIProviderError.incomplete }
        return result
    }
}

public struct ChatGPTAIProvider: AIProvider {
    public let id = "chatgpt"
    public init() {}
    public func models(token: String) async throws -> [AIModelDescriptor] {
        let session = URLSession(configuration: .ephemeral, delegate: AIRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string:"https://api.openai.com/v1/models")!)
        request.timeoutInterval = 20; request.setValue("Bearer " + token, forHTTPHeaderField:"Authorization")
        let (data,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000,
              let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let models = root["models"] as? [[String:Any]] else { throw AIProviderError.unavailable }
        return models.filter { $0["visibility"] as? String == "list" }.compactMap { entry in
            guard let slug = entry["slug"] as? String else { return nil }
            let capabilities = entry["capabilities"] as? [String:Any]
            return AIModelDescriptor(provider:id,model:slug,supportsTools: capabilities?["function_calling"] as? Bool ?? false)
        }
    }
    public func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = URLSession(configuration: .ephemeral, delegate: AIRedirectBlocker(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    guard request.tools.isEmpty || request.model.supportsTools else { throw AIProviderError.unsupportedModel }
                    var http = URLRequest(url: URL(string:"https://api.openai.com/v1/responses")!)
                    http.httpMethod = "POST"; http.timeoutInterval = 90
                    http.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
                    http.setValue("application/json",forHTTPHeaderField:"Content-Type")
                    var body: [String:Any] = ["model":request.model.model,"store":false,"stream":true,
                        "instructions":request.instructions,"input":request.input.map(\.wire)]
                    if !request.tools.isEmpty { body["tools"] = [["type":"namespace","name":"engram","description":"Engram application capabilities","tools":request.tools.map(\.wire)]] }
                    http.httpBody = try JSONSerialization.data(withJSONObject:body)
                    #if !os(Windows)
                    let (bytes,response) = try await session.bytes(for:http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AIProviderError.unavailable }
                    var decoder = AIStreamDecoder(limit: request.outputLimit)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try decoder.accept(line) { continuation.yield(event) }
                        if decoder.completed { break }
                    }
                    guard decoder.completed else { throw AIProviderError.incomplete }
                    #else
                    // FoundationNetworking lacks AsyncBytes. The same validated SSE decoder is used.
                    let (data,response) = try await session.data(for:http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw AIProviderError.unavailable }
                    var decoder = AIStreamDecoder(limit:request.outputLimit)
                    for line in String(decoding:data,as:UTF8.self).components(separatedBy:"\n") {
                        for event in try decoder.accept(line) { continuation.yield(event) }
                    }
                    guard decoder.completed else { throw AIProviderError.incomplete }
                    #endif
                    continuation.finish()
                } catch { continuation.finish(throwing:error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Rejects incomplete/error streams and validates complete call arguments before execution.
public struct AIStreamDecoder {
    public private(set) var completed = false
    private var size = 0
    private var textSize = 0
    private var calls = Set<String>()
    private let limit: Int
    public init(limit: Int = 150_000) { self.limit = limit }
    public mutating func accept(_ line: String) throws -> [AIEvent] {
        guard !completed, line.hasPrefix("data: ") else { return [] }
        let raw = String(line.dropFirst(6)).trimmingCharacters(in:.whitespacesAndNewlines)
        guard raw != "[DONE]", let event = try JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any] else { return [] }
        size += raw.utf8.count
        guard size <= max(limit * 12,1_000_000) else { throw AIProviderError.exceededLimit }
        switch event["type"] as? String {
        case "response.output_text.delta":
            let delta = event["delta"] as? String ?? ""
            textSize += delta.utf8.count
            guard textSize <= limit else { throw AIProviderError.exceededLimit }
            return [.textDelta(delta)]
        case "response.output_item.done":
            return try tool(event["item"] as? [String:Any])
        case "response.failed", "response.incomplete", "error": throw AIProviderError.incomplete
        case "response.completed":
            if let response = event["response"] as? [String:Any], let status = response["status"] as? String, status != "completed" { throw AIProviderError.incomplete }
            var result: [AIEvent] = []
            if let response = event["response"] as? [String:Any], let output = response["output"] as? [[String:Any]] {
                for item in output { result += try tool(item) }
            }
            completed = true; result.append(.completed); return result
        default: return []
        }
    }
    private mutating func tool(_ item: [String:Any]?) throws -> [AIEvent] {
        guard let item, item["type"] as? String == "function_call" else { return [] }
        guard let id = item["call_id"] as? String, !id.isEmpty,
              let name = item["name"] as? String, !name.isEmpty,
              let arguments = item["arguments"] as? String, arguments.utf8.count <= 30_000,
              (try? JSONSerialization.jsonObject(with:Data(arguments.utf8))) is [String:Any] else { throw AIProviderError.invalidTool }
        guard calls.insert(id).inserted else { return [] }
        return [.toolCall(AIToolCall(id:id,name:name,arguments:arguments))]
    }
}
public enum AIClient {
    public static func text(instructions: String, input: String, model: String, token: String, limit: Int = 150_000) async throws -> String {
        let request = AIRequest(model: AIModelDescriptor(provider:"chatgpt",model:model,supportsTools:true),
            instructions:instructions,input:[.message(AIMessage(role:"user",text:input))],outputLimit:limit)
        let response = try await ChatGPTAIProvider().respond(request,token:token)
        guard response.calls.isEmpty else { throw AIProviderError.invalidTool }
        return response.text
    }
}
private final class AIRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

