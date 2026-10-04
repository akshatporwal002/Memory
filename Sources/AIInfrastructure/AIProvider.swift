import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AIModelDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String { provider + ":" + model }
    public var provider: String
    public var model: String
    public var supportsTools: Bool
    public var displayName: String?
    public var toolSupportKnown: Bool?
    public var title: String { displayName ?? model }
    public init(provider: String, model: String, supportsTools: Bool, displayName: String? = nil, toolSupportKnown: Bool = true) {
        self.provider = provider; self.model = model; self.supportsTools = supportsTools
        self.displayName = displayName; self.toolSupportKnown = toolSupportKnown
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
    case message(AIMessage), call(AIToolCall), result(callID: String, output: String), context(AIContextItem)
    var wire: [String: Any] {
        switch self {
        case .message(let message): return ["role":message.role,"content":message.text]
        case .call(let call): return ["type":"function_call","call_id":call.id,"name":call.name,"arguments":call.arguments]
        case .result(let id,let output): return ["type":"function_call_output","call_id":id,"output":output]
        case .context(let item): return item.wire
        }
    }
}
/// Opaque continuation state belongs to the provider adapter, not app action parsing.
public struct AIContextItem: Codable, Equatable, Sendable {
    public let provider: String
    public let json: String
    public init(provider: String,json: String) throws {
        guard json.utf8.count <= 350_000,let value = try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any] else { throw AIProviderError.invalidTool }
        if provider == "gemini" { try GeminiWire.validateContext(value) }
        else { guard ["chatgpt", "openai"].contains(provider),value["type"] as? String == "reasoning",value["id"] is String else { throw AIProviderError.invalidTool } }
        self.provider = provider; self.json = json
    }
    var wire: [String:Any] {
        guard ["chatgpt", "openai"].contains(provider),json.utf8.count <= 350_000,let value = try? JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any],value["type"] as? String == "reasoning" else { return [:] }
        return value.filter { ["id","type","summary","encrypted_content"].contains($0.key) }
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
public enum AIEvent: Sendable, Equatable { case textDelta(String), toolCall(AIToolCall), contextItem(AIContextItem), usage(AIUsage), completed }
public struct AIResponse: Sendable {
    public var text = ""
    public var calls: [AIToolCall] = []
    public var context: [AIInput] = []
    public var usage: AIUsage?
    public var firstTokenMS: Double?
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
        case .incomplete: "AI stopped before completion. Completed actions remain in Review changes."
        case .exceededLimit: "The AI output exceeded its limit. Try a smaller request."
        case .invalidTool: "The AI returned an invalid action. No such action was executed."
        case .unsupportedModel: "This model does not support app actions. Choose a tool-capable model."
        }
    }
}
/// Repair interrupted tool history from durable receipts without repeating mutations.
public enum AIHistoryRecovery {
    public static func reconcile(_ input: [AIInput],receipts: [String:String]) -> [AIInput] {
        let answered = Set(input.compactMap { item -> String? in if case .result(let id,_) = item { return id }; return nil })
        var result: [AIInput] = []
        for item in input {
            result.append(item)
            if case .call(let call) = item,!answered.contains(call.id) {
                result.append(.result(callID:call.id,output:receipts[call.id] ?? "Interrupted before a result was saved. Do not assume success or repeat the mutation. Inspect the current state and ask for continuation."))
            }
        }
        return result
    }
}
public protocol AIProvider: Sendable {
    var id: String { get }
    func models(token: String) async throws -> [AIModelDescriptor]
    func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error>
}
public extension AIProvider {
    func respond(_ request: AIRequest, token: String) async throws -> AIResponse {
        guard request.tools.isEmpty || request.model.supportsTools else { throw AIProviderError.unsupportedModel }
        var result = AIResponse(), completed = false
        let started = Date()
        for try await event in stream(request, token: token) {
            try Task.checkCancellation()
            guard !completed else { throw AIProviderError.incomplete }
            switch event {
            case .textDelta(let text):
                if result.firstTokenMS == nil && !text.isEmpty { result.firstTokenMS = Date().timeIntervalSince(started) * 1000 }
                result.text += text; guard result.text.utf8.count <= request.outputLimit else { throw AIProviderError.exceededLimit }
            case .toolCall(let call):
                guard !result.calls.contains(where: { $0.id == call.id }) else { continue }
                result.calls.append(call)
                result.context.append(.call(call))
            case .contextItem(let item): result.context.append(.context(item))
            case .usage(let usage): result.usage = usage
            case .completed: completed = true
            }
        }
        guard completed else { throw AIProviderError.incomplete }
        return result
    }
}

public struct ChatGPTAIProvider: AIProvider {
    private let apiKeyAccount: Bool
    public var id: String { apiKeyAccount ? "openai" : "chatgpt" }
    public init() { apiKeyAccount = false }
    init(apiKeyAccount: Bool) { self.apiKeyAccount = apiKeyAccount }
    public func models(token: String) async throws -> [AIModelDescriptor] {
        let session = URLSession(configuration: .ephemeral, delegate: AIRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string:"https://api.openai.com/v1/models")!)
        request.timeoutInterval = 20; request.setValue("Bearer " + token, forHTTPHeaderField:"Authorization")
        let (data,response) = try await session.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000,
              let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AIProviderError.unavailable }
        if apiKeyAccount { return try OpenAIAPIProvider.decodeModels(root) }
        guard let models = root["models"] as? [[String:Any]] else { throw AIProviderError.unavailable }
        return models.filter { $0["visibility"] as? String == "list" }.compactMap { entry in
            guard let slug = entry["slug"] as? String else { return nil }
            let capabilities = entry["capabilities"] as? [String:Any]
            let advertised = capabilities?["function_calling"] as? Bool
            return AIModelDescriptor(provider:id,model:slug,supportsTools:advertised ?? false,displayName:entry["display_name"] as? String,toolSupportKnown:advertised != nil)
        }
    }
    /// The catalog does not guarantee capability metadata. Probe only the selected model,
    /// using a harmless local tool which is never executed, rather than guessing from its name.
    public func resolveTools(_ model: AIModelDescriptor,token: String) async throws -> AIModelDescriptor {
        guard model.toolSupportKnown == false else { return model }
        var candidate = model; candidate.supportsTools = true
        let probe = AIToolDefinition(name:"capability_check",summary:"Harmless capability check; no application action.",parametersJSON:#"{"type":"object","properties":{},"additionalProperties":false}"#)
        do { _ = try await respond(AIRequest(model:candidate,instructions:"Capability check only. Reply Ready. Do not call tools.",input:[.message(AIMessage(role:"user",text:"Ready?"))],tools:[probe],outputLimit:2000),token:token) }
        catch AIProviderError.unsupportedModel { candidate.supportsTools = false }
        candidate.toolSupportKnown = true
        return candidate
    }
    public func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = URLSession(configuration: .ephemeral, delegate: AIRedirectBlocker(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                do {
                    guard request.model.provider == id else { throw AIProviderError.unsupportedModel }
                    for item in request.input {
                        if case .context(let context) = item, context.provider != id { throw AIProviderError.invalidTool }
                    }
                    guard request.tools.isEmpty || request.model.supportsTools else { throw AIProviderError.unsupportedModel }
                    var http = URLRequest(url: URL(string:"https://api.openai.com/v1/responses")!)
                    http.httpMethod = "POST"; http.timeoutInterval = 90
                    http.setValue("Bearer " + token,forHTTPHeaderField:"Authorization")
                    http.setValue("application/json",forHTTPHeaderField:"Content-Type")
                    var body: [String:Any] = ["model":request.model.model,"store":false,"stream":true,
                        "instructions":request.instructions,"input":request.input.map(\.wire)]
                    if !request.tools.isEmpty {
                        if apiKeyAccount { body["tools"] = request.tools.map(\.wire) }
                        else { body["tools"] = [["type":"namespace","name":"engram","description":"Engram application capabilities","tools":request.tools.map(\.wire)]] }
                        body["include"] = ["reasoning.encrypted_content"]
                    }
                    http.httpBody = try JSONSerialization.data(withJSONObject:body)
                    #if !os(Windows)
                    let (bytes,response) = try await session.bytes(for:http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        var failure = Data()
                        for try await byte in bytes { guard failure.count < 8000 else { break }; failure.append(byte) }
                        throw Self.failure(failure)
                    }
                    var decoder = AIStreamDecoder(limit: request.outputLimit, provider: id)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        for event in try decoder.accept(line) { continuation.yield(event) }
                        if decoder.completed { break }
                    }
                    guard decoder.completed else { throw AIProviderError.incomplete }
                    #else
                    // FoundationNetworking lacks AsyncBytes. The same validated SSE decoder is used.
                    let (data,response) = try await session.data(for:http)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Self.failure(Data(data.prefix(8000))) }
                    guard data.count <= 2_000_000 else { throw AIProviderError.exceededLimit }
                    var decoder = AIStreamDecoder(limit:request.outputLimit, provider: id)
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
    private static func failure(_ data: Data) -> AIProviderError {
        guard let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any],let error = root["error"] as? [String:Any] else { return .unavailable }
        let message = (error["message"] as? String ?? "").lowercased()
        if (message.contains("tool") || message.contains("function calling")),(message.contains("does not support") || message.contains("not supported by this model")) { return .unsupportedModel }
        return .unavailable
    }
}

/// Rejects incomplete/error streams and validates complete call arguments before execution.
public struct AIStreamDecoder {
    public private(set) var completed = false
    private var size = 0
    private var textSize = 0
    private var calls = Set<String>()
    private var contexts = Set<String>()
    private let limit: Int
    private let provider: String
    public init(limit: Int = 150_000, provider: String = "chatgpt") { self.limit = limit; self.provider = provider }
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
            if let response = event["response"] as? [String: Any], let raw = response["usage"] as? [String: Any], let usage = AIUsage.responses(raw) { result.append(.usage(usage)) }
            completed = true; result.append(.completed); return result
        default: return []
        }
    }
    private mutating func tool(_ item: [String:Any]?) throws -> [AIEvent] {
        guard let item else { return [] }
        if item["type"] as? String == "reasoning" {
            guard let id = item["id"] as? String,contexts.insert(id).inserted else { return [] }
            let data = try JSONSerialization.data(withJSONObject:item.filter { ["id","type","summary","encrypted_content"].contains($0.key) })
            return [.contextItem(try AIContextItem(provider:provider,json:String(decoding:data,as:UTF8.self)))]
        }
        guard item["type"] as? String == "function_call" else { return [] }
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
        try await response(instructions: instructions, input: input, model: model, token: token, limit: limit).text
    }
    public static func response(instructions: String, input: String, model: String, token: String, limit: Int = 150_000) async throws -> AIResponse {
        let descriptor = try AIProviderRegistry.descriptor(model)
        let provider = try AIProviderRegistry.provider(descriptor.provider)
        let request = AIRequest(model: descriptor,
            instructions:instructions,input:[.message(AIMessage(role:"user",text:input))],outputLimit:limit)
        let response = try await provider.respond(request,token:token)
        guard response.calls.isEmpty else { throw AIProviderError.invalidTool }
        return response
    }
}
private final class AIRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

