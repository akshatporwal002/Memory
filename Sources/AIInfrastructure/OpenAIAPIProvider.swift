import Foundation

/// Personal API billing is separate from a ChatGPT plan's OAuth entitlement.
public struct OpenAIAPIProvider: AIProvider {
    public let id = "openai"
    private let transport = ChatGPTAIProvider(apiKeyAccount: true)
    public init() {}
    public func models(token: String) async throws -> [AIModelDescriptor] {
        try await transport.models(token: token)
    }
    public func resolveTools(_ model: AIModelDescriptor, token: String) async throws -> AIModelDescriptor {
        try await transport.resolveTools(model, token: token)
    }
    public func stream(_ request: AIRequest, token: String) -> AsyncThrowingStream<AIEvent, Error> {
        transport.stream(request, token: token)
    }
    static func decodeModels(_ root: [String: Any]) throws -> [AIModelDescriptor] {
        guard let entries = root["data"] as? [[String: Any]] else { throw AIProviderError.unavailable }
        var seen = Set<String>()
        return entries.compactMap { entry in
            guard let model = entry["id"] as? String, !model.isEmpty, model.utf8.count <= 200,
                  seen.insert(model).inserted else { return nil }
            // Model listing establishes access, not chat/audio/tool capabilities.
            return AIModelDescriptor(provider: "openai", model: model, supportsTools: false, toolSupportKnown: false)
        }
    }
}
