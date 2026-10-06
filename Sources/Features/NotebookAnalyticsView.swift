import SwiftUI
import LearningCore
import StudyApplication
import DesignSystem

struct NotebookAnalyticsView: View {
    @Bindable var model: EngramModel
    let deckID: String
    @State private var analytics: NotebookAnalytics?
    @State private var error: String?
    var body: some View {
        Form {
            if let analytics {
                EngramListSection("Observed outcomes") {
                    LabeledContent("Accepted attempts", value: String(analytics.observed.acceptedAttempts))
                    LabeledContent("Delayed recall", value: analytics.observed.delayedRecall.label)
                    LabeledContent("Unfamiliar questions", value: analytics.observed.unfamiliarQuestions.label)
                    LabeledContent("Measured study time", value: analytics.observed.measuredStudySeconds.map { "\(Int($0 / 60)) min · \(analytics.observed.timedAttempts) timed attempts" } ?? "Insufficient evidence")
                    ForEach(analytics.observed.skillErrors.keys.sorted(), id: \.self) { skill in
                        LabeledContent(skill, value: "\(analytics.observed.skillErrors[skill]!) confirmed errors")
                    }
                    Text(analytics.observed.comparison).font(.caption).engramSecondaryText()
                }
                EngramListSection("FSRS · recall") {
                    LabeledContent("Predicted recall now", value: analytics.predictedRecall.map { $0.formatted(.percent) } ?? "Insufficient evidence")
                    Text("\(analytics.recallEstimatedCards) / \(analytics.recallTotalCards) cards estimated. Model prediction, not an observed test result.").font(.caption).engramSecondaryText()
                    Text("The notebook's Memory outlook shows predicted recall over time. Recall estimates are separate from topic mastery and application performance.").font(.subheadline)
                    let noteIDs = Set(model.library.liveNotes.filter { $0.deckID == deckID }.map(\.id))
                    let cards = model.library.liveCards.filter { $0.deckID == deckID && !$0.suspended && noteIDs.contains($0.noteID) }
                    LabeledContent("Scheduled cards", value: String(cards.count))
                    LabeledContent("Ready now", value: String(cards.filter { $0.schedule.due <= model.now }.count))
                }
                ForEach(analytics.components, id: \.description.model.rawValue) { component in
                    EngramListSection(component.description.model.rawValue) {
                        Text(component.description.purpose).font(.subheadline)
                        LabeledContent("State", value: component.mode.rawValue.capitalized)
                        Text(component.description.readiness).font(.caption).engramSecondaryText()
                        let predicted = component.questions.filter { $0.prediction != nil }
                        if predicted.isEmpty {
                            Text("Insufficient evidence or model Off").font(.subheadline)
                            if component.description.model == .dina { Text("Diagnosis requires a supported assessment administration; ordinary practice is not a diagnostic form.").font(.caption).engramSecondaryText() }
                        } else {
                            ForEach(predicted) { question in
                                DisclosureGroup {
                                    if let prediction = question.prediction {
                                        if let probability = prediction.probabilityCorrect { LabeledContent("Predicted correct", value: probability.formatted(.percent)) }
                                        if let difficulty = question.calibratedDifficulty { LabeledContent("Calibrated item difficulty", value: difficulty.formatted()); Text("Rasch scale units; higher is harder. Comparable only within the same anchored artifact.").font(.caption).engramSecondaryText() }
                                        if let mean = prediction.abilityMean { LabeledContent("Conditional ability", value: mean.formatted()) }
                                        if let lower = prediction.abilityLower, let upper = prediction.abilityUpper { Text("Conditional 95% interval: \(lower.formatted())–\(upper.formatted())").font(.caption) }
                                        if let skills = prediction.skillProbabilities {
                                            ForEach(skills.keys.sorted(), id: \.self) { skill in LabeledContent("Mastery estimate · " + skill, value: skills[skill]!.formatted(.percent)) }
                                        }
                                        Text("Artifact \(prediction.artifactRevision) · evidence revision \(prediction.evidenceRevision)").font(.caption).engramSecondaryText()
                                    }
                                } label: { Text(question.prompt).font(.subheadline).lineLimit(3) }
                            }
                        }
                        Text(component.description.limitations).font(.caption).engramSecondaryText()
                        if component.description.model == .das3h { Text("Performance predictions are not topic-mastery percentages.").font(.caption).engramSecondaryText() }
                    }
                }
                EngramListSection {
                    Text("Observed outcomes belong to this notebook. Predictions may use compatible evidence across notebooks in this library. Estimates are conditional on the selected model; no cross-model ranking is implied.").font(.caption).engramSecondaryText()
                    NavigationLink("Learning & practice settings") { UnderstandingSettingsView(model: model, deckID: deckID) }
                }
            } else if let error { EngramListSection { Text(error).font(.subheadline) } }
            else { ProgressView("Loading analytics") }
        }.modifier(UtilityListStyle()).navigationTitle("Analytics")
            .task(id: model.library.revision) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        let account = model.understanding.account(model), library = model.activeLibraryID
        analytics = nil; error = nil
        await model.understanding.configure(model)
        do {
            let result = try await model.service.notebookAnalytics(deckID: deckID, now: model.now)
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            analytics = result
        } catch {
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            self.error = "Analytics unavailable. Try refreshing after the current attempt finishes."
        }
    }
}
