import Foundation
import LearningCore

/// Isolated illustration: toy parameters and synthetic responses never enter the
/// learner store, calibration reports, research exports, or personal model selection.
public enum LearningAnalyticsDemo {
    static let marker = "engram-learning-analytics-demo-v1"
    static let skills = ["Fractions", "Equations", "Probability"]
    static let prompts = ["Write one half as a decimal.", "Add one quarter and one half.", "Simplify six eighths.",
                          "Solve x + 3 = 7.", "Solve 2x = 10.", "Solve 3x − 2 = 7.",
                          "What is the chance of heads on a fair coin?", "What is the chance of rolling a six?", "What is the chance of two heads in a row?"]
    static let answers = ["0.5", "3/4", "3/4", "x = 4", "x = 5", "x = 3", "1/2", "1/6", "1/4"]
    public static func isDemo(_ deck: Deck) -> Bool { deck.id.hasSuffix("-" + marker) && deck.sourceDocument?.hasPrefix(marker) == true }

    static func analytics(deck: Deck, snapshot: LibrarySnapshot, scheduler: any Scheduler, now: Date) throws -> NotebookAnalytics {
        let end = min(deck.createdAt ?? now, now)
        let mappings = try prompts.indices.map { index in
            try ReviewedSkillMapping(questionID: deck.id + "-q\(index)-card", questionVersion: 1,
                revision: marker, skillIDs: [skills[index / 3]], reviewedBy: "Synthetic demonstration")
        }
        var evidence: [LearnerEvidence] = []
        for day in 0..<28 {
            for i in prompts.indices {
                let correct = (day * 7 + i * 3) % 10 < min(9, 4 + day / 5 + (i / 3 == 0 ? 1 : 0))
                let assessment = day == 27
                evidence.append(LearnerEvidence(attemptID: "demo-\(day)-\(i)", revision: 1, questionID: mappings[i].questionID,
                    questionVersion: 1, occurredAt: end.addingTimeInterval(Double(day - 28) * 86400 + Double(i) * 60),
                    kind: day % 2 == 0 ? .recall : .fixedApplication, mapping: mappings[i], assisted: false,
                    acceptance: .accepted, correct: correct, gradingMethod: "synthetic-demo", unfamiliar: day % 2 != 0,
                    delaySeconds: day % 2 == 0 ? 172800 : nil, studySeconds: Double(35 + (27 - day) * 2 + i * 3),
                    errorSkillIDs: correct ? [] : mappings[i].skillIDs, assessmentID: assessment ? marker : nil,
                    assessmentSessionID: assessment ? "demo-assessment" : nil))
            }
        }
        let items = mappings.enumerated().map { i, m in DAS3HLearnerPredictor.Item(questionID: m.questionID, questionVersion: 1, difficulty: Double(i % 3) * 0.6 - 0.5) }
        let report = "Synthetic toy parameters; not fitted or validated."
        let bkt = BKTLearnerPredictor(artifact: .init(revision: marker, mappingRevision: marker, trainingReport: report,
            heldOutValidationReport: report, parameters: Dictionary(uniqueKeysWithValues: skills.map { ($0, .init(prior: 0.25, learn: 0.04, guess: 0.2, slip: 0.15)) })))
        let das = DAS3HLearnerPredictor(artifact: .init(revision: marker, mappingRevision: marker, trainingReport: report,
            heldOutValidationReport: report, ability: -0.2, windows: [86400, 604800, nil],
            skills: Dictionary(uniqueKeysWithValues: skills.map { ($0, .init(easiness: 0, wins: [0.5, 0.6, 0.7], attempts: [0.25, 0.3, 0.4])) }), items: items))
        let grid = (-12...12).map { Double($0) / 4 }
        let rasch = DynamicRaschLearnerPredictor(artifact: .init(revision: marker, trainingReport: report,
            heldOutValidationReport: report, scaleAnchor: "Synthetic scale", grid: grid,
            prior: Array(repeating: 1 / Double(grid.count), count: grid.count), variancePerDay: 0.04, items: items))
        let dina = DINALearnerPredictor(artifact: .init(revision: marker, assessmentID: marker, trainingReport: report,
            heldOutValidationReport: report, skillIDs: skills, profilePrior: Array(repeating: 0.125, count: 8),
            items: mappings.map { .init(mapping: $0, slip: 0.15, guess: 0.2) }))
        let adapters: [any LearnerPredictor] = [das, bkt, rasch, dina]
        var components: [NotebookAnalytics.Component] = []
        for description in LearnerModelDescription.catalog(predictors: adapters, history: evidence) {
            let adapter = adapters.first { $0.model == description.model }!
            let history = adapter.selectHistory(evidence.filter(adapter.compatible))
            let payload = try adapter.replay(history)
            let questions = try mappings.enumerated().map { index, mapping in
                var probability: Double?, mastery: [String: Double]?, mean: Double?, lower: Double?, upper: Double?
                switch description.model {
                case .das3h: probability = try das.probability(mapping: mapping, at: now, history: payload)
                case .bkt:
                    probability = try bkt.probability(mapping: mapping, history: payload)
                    mastery = try bkt.mastery(mapping: mapping, history: payload)
                case .dynamicRasch:
                    probability = try rasch.probability(questionID: mapping.questionID, questionVersion: 1, at: now, history: payload)
                    let ability = try rasch.ability(at: now, history: payload)
                    mean = ability.mean; lower = ability.lower; upper = ability.upper
                case .dina:
                    probability = try dina.probability(mapping: mapping, history: payload)
                    mastery = try dina.skillProbabilities(history: payload)
                }
                let prediction = LearnerPrediction(model: description.model, artifactRevision: marker, probabilityCorrect: probability,
                    skillProbabilities: mastery, abilityMean: mean, abilityLower: lower, abilityUpper: upper,
                    evidenceRevision: evidence.count, mode: .observe, compatibleAttempts: history.count)
                return NotebookAnalytics.Question(prompt: prompts[index], mapping: mapping, prediction: prediction,
                    calibratedDifficulty: description.model == .dynamicRasch ? items[index].difficulty : nil)
            }
            var component = NotebookAnalytics.Component(description: description, mode: .observe, questions: questions)
            if description.model == .dynamicRasch { component.abilityHistory = try NotebookAnalytics.abilityPoints(rasch, evidence: history, now: now) }
            components.append(component)
        }
        let cards = snapshot.liveCards.filter { $0.deckID == deck.id }
        let forecast = NotebookAnalytics.forecast(cards: cards, scheduler: scheduler, settings: snapshot.settings, now: now)
        var result = NotebookAnalytics(observed: LearnerDashboard(evidence: evidence), components: components, recordingEnabled: false,
            predictedRecall: forecast.first?.value, recallEstimatedCards: cards.count, recallTotalCards: cards.count)
        result.isDemo = true; result.evidence = evidence; result.recallForecast = forecast
        return result
    }
}

extension StudyService {
    /// Idempotent, scoped to the current library. Deleted demos stay deleted.
    @discardableResult public func importLearningAnalyticsDemo(now: Date = Date()) async throws -> String {
        var library = try await repository.read()
        let deckID = "sample-" + (await selectedLibraryID()) + "-" + LearningAnalyticsDemo.marker
        if library.decks.contains(where: { $0.id == deckID }) { return deckID }
        let name = "Learning lab · Sample data"
        guard !library.liveDecks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { throw EngramError.invalid("Rename the existing Learning lab notebook before adding the sample.") }
        var deck = Deck(id: deckID, name: name, createdAt: now, modifiedAt: now)
        deck.sourceDocument = LearningAnalyticsDemo.marker + "\n\nSynthetic learning history for exploring FSRS, DAS3H, BKT, dynamic IRT and DINA charts. Toy parameters are illustrative, not calibrated. This is not your learning record."
        library.decks.append(deck)
        for i in LearningAnalyticsDemo.prompts.indices {
            let noteID = deckID + "-q\(i)"
            library.notes.append(Note(id: noteID, deckID: deckID, kind: .basic, front: LearningAnalyticsDemo.prompts[i],
                back: LearningAnalyticsDemo.answers[i], tags: [LearningAnalyticsDemo.marker], source: "Original synthetic demonstration", modifiedAt: now))
            var schedule = try scheduler.initialState(now: now.addingTimeInterval(-28 * 86400), settings: library.settings)
            for day in [0, 1, 3, 7, 14, 24] {
                let date = now.addingTimeInterval(Double(day - 28) * 86400)
                let outcomes = try scheduler.outcomes(state: schedule, history: [], now: date, settings: library.settings)
                schedule = outcomes[i % 3 == 2 && day == 14 ? .again : .good] ?? schedule
            }
            library.cards.append(StudyCard(id: noteID + "-card", noteID: noteID, deckID: deckID, schedule: schedule, suspended: true))
        }
        // Suspended sample cards keep the illustration out of the user's review queue.
        try LibraryValidation.validate(library)
        try await repository.commit(library, expectedRevision: library.revision)
        return deckID
    }
}
