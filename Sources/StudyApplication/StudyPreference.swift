import Foundation
import LearningCore

/// Each control changes one preference so stale view drafts cannot overwrite other fields.
public enum StudyPreference: Sendable {
    case newCards(Int), reviews(Int), dayStarts(Int), timeZone(String), retention(Double)
    func apply(to settings: inout StudySettings) {
        switch self {
        case .newCards(let value): settings.newCardsPerDay = value
        case .reviews(let value): settings.reviewsPerDay = value
        case .dayStarts(let value): settings.dayStartsAtHour = value
        case .timeZone(let value): settings.timeZoneID = value
        case .retention(let value): settings.desiredRetention = value
        }
    }
}

extension StudyService {
    public func updatePreference(_ preference: StudyPreference) async throws {
        var library = try await repository.read()
        preference.apply(to: &library.settings)
        library.settings.version += 1
        // Retention changes invalidate unrevealed scheduling previews. Preserve graded feedback.
        if case .retention = preference, let current = library.session?.current, current.assessment == nil {
            library.session?.current = ReviewPresentation(card: current.card)
        }
        try LibraryValidation.validate(library)
        try await repository.commit(library, expectedRevision: library.revision)
    }
}
