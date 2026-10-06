import Foundation
import LearningCore

public struct NotebookAnalytics: Sendable {
    public struct Question: Identifiable, Sendable {
        public var id: String { mapping.questionID + ":" + String(mapping.questionVersion) }
        public let prompt: String
        public let mapping: ReviewedSkillMapping
        public let prediction: LearnerPrediction?
        public let calibratedDifficulty: Double?
    }
    public struct Component: Sendable {
        public let description: LearnerModelDescription
        public let mode: LearnerMode
        public let questions: [Question]
    }
    public let observed: LearnerDashboard
    public let components: [Component]
    public let recordingEnabled: Bool
    public let predictedRecall: Double?
    public let recallEstimatedCards: Int
    public let recallTotalCards: Int
}

extension StudyService {
    /// Notebook-local outcomes; predictions retain compatible shared library history.
    /// Read-only: opening analytics neither prepares nor activates a model.
    public func notebookAnalytics(deckID: String, now: Date = Date()) async throws -> NotebookAnalytics {
        guard let coordinator = learnerCoordinator else { throw LearnerError.unavailable }
        let context = try await coordinator.context()
        guard context.snapshot.liveDecks.contains(where: { $0.id == deckID }) else { throw LearnerError.unavailable }
        let workspace = try await coordinator.store.workspace(account: context.account, library: context.library)
        let state = try await coordinator.store.load(account: context.account, library: context.library)
        let notes = context.snapshot.liveNotes.filter { $0.deckID == deckID }
        let noteIDs = Set(notes.map(\.id))
        var ids = Set(context.snapshot.cards.filter { noteIDs.contains($0.noteID) }.map(\.id))
        for note in notes { for variant in note.questionFamily?.variants ?? [] { ids.insert(note.id + ":variant:" + variant.id) } }
        // Saved attempt identities survive replacing a question family.
        let attempts = workspace.understanding?.sessions.filter { $0.deckID == deckID }.flatMap(\.attempts) ?? []
        let attemptIDs = Set(attempts.map(\.id))
        let evidence = state.latest.filter { ids.contains($0.questionID) || attemptIDs.contains($0.attemptID) }
        let predictors = try LearnerModelID.allCases.compactMap { try workspace.candidate(for: $0, state: state)?.predictor() }
        let catalog = LearnerModelDescription.catalog(predictors: predictors, history: state.latest)
        var reviewed: [ReviewedLearnerQuestion] = []
        for question in workspace.questions where ids.contains(question.mapping.questionID) {
            let currentRecall = context.snapshot.cards.contains { card in
                guard card.id == question.mapping.questionID, noteIDs.contains(card.noteID), let note = notes.first(where: { $0.id == card.noteID }),
                      let rendered = try? CardRenderer.render(note: note, card: card, revealed: true) else { return false }
                return rendered.prompt == question.prompt && rendered.answer == question.expectedAnswer
            }
            let currentVariant = notes.contains { note in
                note.questionFamily?.available(in: context.snapshot, note: note).contains { variant in
                    variant.validation?.mapping == question.mapping && variant.front == question.prompt && variant.back == question.expectedAnswer
                } == true
            }
            if currentRecall || currentVariant {
                if let i = reviewed.firstIndex(where: { $0.mapping.questionID == question.mapping.questionID }) { reviewed[i] = question }
                else { reviewed.append(question) }
            }
        }
        var components: [NotebookAnalytics.Component] = []
        for entry in catalog {
            let selected: LearnerModelID
            switch entry.model.purpose { case .skill: selected = state.configuration.skill; case .difficulty: selected = state.configuration.difficulty; case .diagnosis: selected = state.configuration.diagnosis }
            let mode: LearnerMode = selected == entry.model ? state.configuration.modes[entry.model.purpose] ?? .off : .off
            var rows: [NotebookAnalytics.Question] = []
            for question in reviewed.sorted(by: { $0.mapping.questionID < $1.mapping.questionID }) {
                let capture = workspace.captures.last { $0.mapping == question.mapping && $0.assessmentID != nil && $0.assessmentSessionID != nil }
                let prediction = try? await learnerPrediction(model: entry.model, questionID: question.mapping.questionID,
                    questionVersion: question.mapping.questionVersion, mapping: question.mapping,
                    assessmentID: capture?.assessmentID, assessmentSessionID: capture?.assessmentSessionID, now: now)
                var difficulty: Double?
                if prediction != nil, entry.model == .dynamicRasch, let candidate = workspace.candidate(for: entry.model, state: state) {
                    let artifact = try JSONDecoder().decode(DynamicRaschLearnerPredictor.Artifact.self, from: candidate.parameters)
                    difficulty = artifact.items.first { $0.questionID == question.mapping.questionID && $0.questionVersion == question.mapping.questionVersion }?.difficulty
                }
                rows.append(.init(prompt: question.prompt, mapping: question.mapping, prediction: prediction, calibratedDifficulty: difficulty))
            }
            components.append(.init(description: entry, mode: mode, questions: rows))
        }
        try await coordinator.check(context)
        let current = try await coordinator.store.load(account: context.account, library: context.library)
        guard current.revision == state.revision, current.configuration == state.configuration else { throw LearnerError.conflict }
        let cards = context.snapshot.liveCards.filter { $0.deckID == deckID && !$0.suspended && noteIDs.contains($0.noteID) }
        let estimates = cards.compactMap { (scheduler as? any MemoryEstimating)?.recallProbability(state: $0.schedule, now: now, settings: context.snapshot.settings) }
        return NotebookAnalytics(observed: LearnerDashboard(evidence: evidence), components: components, recordingEnabled: workspace.recordingEnabled,
            predictedRecall: estimates.isEmpty ? nil : estimates.reduce(0, +) / Double(estimates.count), recallEstimatedCards: estimates.count, recallTotalCards: cards.count)
    }
}
