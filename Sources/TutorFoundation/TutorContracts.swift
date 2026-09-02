import Foundation
import LearningCore

/// Stable evidence supplied by the user or a future retrieval adapter. A tutor cannot cite anything else.
public struct TutorSource: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let locator: String
    public let version: String?
    public let excerpt: String

    public init(id: String, title: String, locator: String, version: String? = nil, excerpt: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngramError.invalid("Tutor sources require an identifier, title, locator, and excerpt.")
        }
        self.id = id; self.title = title; self.locator = locator; self.version = version; self.excerpt = excerpt
    }
}

public struct TutorQuestion: Codable, Equatable, Sendable {
    public let text: String
    public let sources: [TutorSource]
    public init(text: String, sources: [TutorSource]) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngramError.invalid("A tutor question is required.")
        }
        self.text = text; self.sources = sources
    }
}

/// Provider-neutral draft. Providers cannot mutate cards, grades, scheduling, or mastery through this type.
public struct TutorDraft: Codable, Equatable, Sendable {
    public let text: String
    public let citedSourceIDs: [String]
    public init(text: String, citedSourceIDs: [String]) { self.text = text; self.citedSourceIDs = citedSourceIDs }
}

public enum TutorOutcome: Codable, Equatable, Sendable {
    case answer(text: String, citations: [TutorSource])
    case insufficientEvidence(message: String)
    case unavailable(message: String)
}

/// A provider adapter may be cloud, local, or deterministic. It receives evidence explicitly and returns a draft only.
public protocol TutorProvider: Sendable {
    func answer(question: TutorQuestion) async throws -> TutorDraft
}

/// Enforces evidence references before a provider response becomes visible. Grounding does not establish correctness;
/// the caller presents sources and preserves abstentions as distinct outcomes.
public struct GroundedTutor: Sendable {
    private let provider: any TutorProvider
    public init(provider: any TutorProvider) { self.provider = provider }

    public func answer(_ question: TutorQuestion) async -> TutorOutcome {
        guard !question.sources.isEmpty else {
            return .insufficientEvidence(message: "Add a source excerpt before asking the tutor.")
        }
        do {
            let draft = try await provider.answer(question: question)
            guard !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .insufficientEvidence(message: "The tutor did not return an answer supported by the supplied sources.")
            }
            let sourceByID = Dictionary(uniqueKeysWithValues: question.sources.map { ($0.id, $0) })
            let uniqueIDs = Array(Set(draft.citedSourceIDs))
            guard !uniqueIDs.isEmpty else {
                return .insufficientEvidence(message: "The tutor response has no inspectable source reference.")
            }
            guard uniqueIDs.allSatisfy({ sourceByID[$0] != nil }) else {
                return .insufficientEvidence(message: "The tutor response cited a source that was not supplied.")
            }
            let citations = uniqueIDs.compactMap { sourceByID[$0] }.sorted { $0.id < $1.id }
            return .answer(text: draft.text, citations: citations)
        } catch {
            return .unavailable(message: "The tutor service is unavailable. Your study data was not changed.")
        }
    }
}
