import Foundation
import LearningCore

extension StudyService {
    /// Caller reviews source grounding, same-level scope and rubric before saving. No AI calls here.
    public func saveQuestionVariants(noteID: String, originalFront: String, originalBack: String,
                                     variants: [QuestionVariant], expectedRevision: Int, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard library.revision == expectedRevision, let index = library.notes.firstIndex(where: { $0.id == noteID && !$0.deleted }) else { throw EngramError.conflict }
        let note = library.notes[index]
        guard note.kind == .basic, note.front == originalFront, note.back == originalBack,
              (1...4).contains(variants.count), Set(variants.map(\.id)).count == variants.count,
              Set(variants.map(\.approach)).count == variants.count,
              Set(variants.map { $0.front.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == variants.count,
              variants.allSatisfy({ $0.front != note.front }) else { throw EngramError.invalid("Choose distinct approaches for the unchanged original question.") }
        let sources = EvidenceRetrieval.retrieve(query: note.front, deckID: note.deckID, library: library, preferredNoteID: note.id, limit: 8)
        for variant in variants {
            try variant.validate()
            guard variant.evidence.allSatisfy({ source in sources.contains { $0.id == source.id && $0.version == source.version && $0.text == source.text } && EvidenceRetrieval.isCurrent(source, in: library) }) else {
                throw EngramError.invalid("Source evidence changed or is outside this question's retrieved material.")
            }
        }
        var normalized = variants
        for index in normalized.indices {
            if let old = note.questionFamily?.variants.first(where: { $0.id == normalized[index].id }),
               old.front != normalized[index].front || old.back != normalized[index].back || old.rubric != normalized[index].rubric || old.objective != normalized[index].objective || old.approach != normalized[index].approach || old.evidence != normalized[index].evidence {
                normalized[index].revision = (old.revision ?? 1) + 1
                if normalized[index].validation?.mapping.questionVersion != normalized[index].revision { normalized[index].validation = nil }
            }
            if let validation = normalized[index].validation {
                guard validation.supports(normalized[index], questionID: note.id + ":variant:" + normalized[index].id) else { throw LearnerError.invalidEvidence }
            }
        }
        var family = QuestionFamily(originalFront: note.front, originalBack: note.back, variants: normalized, reviewedAt: now)
        let old = note.questionFamily
        family.exposedVariantIDs = old?.exposedVariantIDs.filter { id, _ in old?.variants.first(where: { $0.id == id }) == variants.first(where: { $0.id == id }) } ?? [:]
        library.notes[index].questionFamily = family
        // Scheduling/content identity is unchanged. No cards, reviews or notebook blocks are touched.
        try await repository.commit(library, expectedRevision: library.revision)
    }
    public func recordQuestionVariantExposure(noteID: String, variantID: String, now: Date = Date()) async throws {
        var library = try await repository.read()
        guard let index = library.notes.firstIndex(where: { $0.id == noteID && !$0.deleted }),
              let family = library.notes[index].questionFamily,
              family.available(in: library, note: library.notes[index]).contains(where: { $0.id == variantID }) else { throw EngramError.missing("question variant") }
        if family.exposedVariantIDs[variantID] != nil { return }
        library.notes[index].questionFamily?.exposedVariantIDs[variantID] = now
        try await repository.commit(library, expectedRevision: library.revision)
    }
}
