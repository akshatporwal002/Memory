import Foundation

public struct AIUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cachedTokens: Int?
    public let reasoningTokens: Int?
    public init?(inputTokens: Int, outputTokens: Int, cachedTokens: Int? = nil, reasoningTokens: Int? = nil) {
        guard inputTokens >= 0, outputTokens >= 0, cachedTokens.map({ $0 >= 0 }) ?? true, reasoningTokens.map({ $0 >= 0 }) ?? true else { return nil }
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cachedTokens = cachedTokens; self.reasoningTokens = reasoningTokens
    }
    public static func responses(_ object: [String: Any]) -> Self? {
        guard let input = object["input_tokens"] as? Int, let output = object["output_tokens"] as? Int else { return nil }
        return Self(inputTokens: input, outputTokens: output, cachedTokens: (object["input_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int,
                    reasoningTokens: (object["output_tokens_details"] as? [String: Any])?["reasoning_tokens"] as? Int)
    }
    public static func gemini(_ object: [String: Any]) -> Self? {
        guard let input = object["promptTokenCount"] as? Int, let output = object["candidatesTokenCount"] as? Int else { return nil }
        return Self(inputTokens: input, outputTokens: output, cachedTokens: object["cachedContentTokenCount"] as? Int, reasoningTokens: object["thoughtsTokenCount"] as? Int)
    }
}
