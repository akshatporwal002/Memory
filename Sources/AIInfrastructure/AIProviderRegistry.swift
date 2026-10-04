import Foundation

public enum AIProviderRegistry {
    public static func provider(_ id: String) throws -> any AIProvider {
        switch id {
        case "chatgpt": return ChatGPTAIProvider()
        case "openai": return OpenAIAPIProvider()
        case "gemini": return GeminiAIProvider()
        default: throw AIProviderError.unavailable
        }
    }
    /// Legacy unqualified selections belong only to the original ChatGPT adapter.
    public static func descriptor(_ selection: String) throws -> AIModelDescriptor {
        let parts = selection.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else { throw AIProviderError.unsupportedModel }
        if parts.count == 1 { return AIModelDescriptor(provider: "chatgpt", model: parts[0], supportsTools: false) }
        _ = try provider(parts[0])
        guard !parts[1].isEmpty else { throw AIProviderError.unsupportedModel }
        return AIModelDescriptor(provider: parts[0], model: parts[1], supportsTools: false)
    }
}
