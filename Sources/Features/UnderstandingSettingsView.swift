import SwiftUI
import LearningCore
import StudyApplication
import DesignSystem
import UniformTypeIdentifiers

struct UnderstandingSettingsView: View {
    @Bindable var model: EngramModel
    let deckID: String?
    @State private var settings = UnderstandingSettings()
    @State private var inherited = true
    @State private var loaded = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if deckID != nil { EngramListSection { Toggle("Use app defaults", isOn: $inherited) } }
            EngramListSection {
                Toggle("Understanding practice", isOn: $settings.enabled)
                Stepper("\(settings.variantCount) alternatives + original", value: $settings.variantCount, in: 1...4)
                Toggle("Allow harder progression", isOn: $settings.harderProgression)
                Picker("Deeper review", selection: $settings.reviewTiming) {
                    Text("Background batches").tag(UnderstandingSettings.ReviewTiming.background)
                    Text("At session end").tag(UnderstandingSettings.ReviewTiming.sessionEnd)
                }
                Stepper("Batch size: \(settings.batchSize)", value: $settings.batchSize, in: 1...10)
                if model.understanding.quickAvailable { Toggle("Laya provisional marks", isOn: $settings.quickFeedback) }
                else { LabeledContent("Laya provisional marks", value: "Runtime unavailable") }
            } footer: { Text("Same-level variety by default. Background batches run while the app is active. Session-end batches may reduce repeated prompt overhead. Harder questions additionally require suitable calibrated predictions.") }
                .disabled(deckID != nil && inherited)
            if deckID == nil {
                EngramListSection {
                    Toggle("Record learner evidence in this library", isOn: Binding(get: { model.understanding.status?.recordingEnabled ?? false }, set: { enabled in
                        Task {
                            do { try await model.service.setLearnerRecordingEnabled(enabled); await model.understanding.refresh(model) }
                            catch { model.understanding.error = error.localizedDescription }
                        }
                    }))
                } footer: { Text("Device-local evidence is separate from research consent and uploads. Unknown historical metadata is not backfilled.") }
            }
            EngramListSection {
                DisclosureGroup("Advanced models") {
                    if let status = model.understanding.status {
                        ForEach(status.models, id: \.model.rawValue) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.model.rawValue).font(.headline)
                                Text(entry.purpose).font(.subheadline)
                                Text(entry.limitations).font(.caption).engramSecondaryText()
                                Text(entry.evidenceStrength + " · " + entry.readiness).font(.caption).engramSecondaryText()
                                if entry.selectable {
                                    Button("Use for " + entry.model.purpose.rawValue) { select(entry.model) }
                                    if selected(entry.model) {
                                        Picker("State", selection: Binding(get: { settings.configuration.modes[entry.model.purpose] ?? .off }, set: { settings.configuration.modes[entry.model.purpose] = $0 })) {
                                            Text("Off").tag(LearnerMode.off); Text("Observe").tag(LearnerMode.observe); Text("Active").tag(LearnerMode.active)
                                        }
                                    }
                                } else {
                                    Text("Informational until ready").font(.caption).engramSecondaryText()
                                }
                            }.disabled(deckID != nil && inherited)
                        }
                        Text("Selections apply between sessions. Observe never changes question order; Active can. Recall remains FSRS.").font(.caption).engramSecondaryText()
                        NavigationLink("Fitting & assessment evidence") { LearnerFittingView(model: model) }
                    }
                }
                NavigationLink("Personal learning") { LearnerDashboardView(model: model) }
                ForEach(model.understanding.sessions.suffix(10).reversed()) { session in
                    Button("Review " + (model.library.liveDecks.first(where: { $0.id == session.deckID })?.name ?? "previous session")) {
                        model.understanding.currentID = session.id; model.understanding.presented = true
                    }
                }
            }
            if let error = model.understanding.error { EngramListSection { Text(error).font(.caption) } }
        }.modifier(UtilityListStyle()).navigationTitle("Learning & practice")
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        do {
                            if let deckID { try await model.service.setUnderstandingSettings(deckID: deckID, settings: inherited ? nil : settings, expectedRevision: model.library.revision); await model.refresh() }
                            else { try model.understanding.saveDefaults(settings) }
                            dismiss()
                        } catch { model.understanding.error = error.localizedDescription }
                    }
                }.disabled(!loaded)
            } }
            .task {
                await model.understanding.refresh(model)
                let override = deckID.flatMap { id in model.library.liveDecks.first { $0.id == id }?.understandingSettings }
                settings = override ?? model.understanding.defaults; inherited = override == nil; loaded = true
            }
            .onChange(of: inherited) { _, value in if value { settings = model.understanding.defaults } }
    }
    private func select(_ id: LearnerModelID) {
        switch id.purpose { case .skill: settings.configuration.skill = id; case .difficulty: settings.configuration.difficulty = id; case .diagnosis: settings.configuration.diagnosis = id }
    }
    private func selected(_ id: LearnerModelID) -> Bool {
        switch id.purpose { case .skill: settings.configuration.skill == id; case .difficulty: settings.configuration.difficulty == id; case .diagnosis: settings.configuration.diagnosis == id }
    }
}

private struct LearnerDashboardView: View {
    @Bindable var model: EngramModel
    var body: some View {
        Form {
            if let status = model.understanding.status {
                EngramListSection {
                    LabeledContent("Delayed recall", value: status.dashboard.delayedRecall.label)
                    LabeledContent("Unfamiliar questions", value: status.dashboard.unfamiliarQuestions.label)
                    LabeledContent("Measured study time", value: status.dashboard.measuredStudySeconds.map { "\(Int($0 / 60)) min · \(status.dashboard.timedAttempts) timed attempts" } ?? "Insufficient evidence")
                    ForEach(status.dashboard.skillErrors.keys.sorted(), id: \.self) { skill in LabeledContent(skill, value: "\(status.dashboard.skillErrors[skill]!) confirmed errors") }
                    Text(status.dashboard.comparison).font(.caption).engramSecondaryText()
                } footer: { Text("Observed outcomes, not model predictions. Viewing a related answer is exposure, not an unfamiliar transfer assessment.") }
                EngramListSection {
                    ForEach(model.understanding.sessions.filter { $0.endedAt != nil }.suffix(10)) { session in
                        LabeledContent(model.library.liveDecks.first { $0.id == session.deckID }?.name ?? "Session", value: "\(session.attempts.filter { $0.assessment?.outcome == .correct }.count) correct · \(session.attempts.filter { $0.status == .assessed }.count) assessed")
                    }
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Personal learning").task { await model.understanding.refresh(model) }
    }
}

private struct LearnerFittingView: View {
    @Bindable var model: EngramModel
    @State private var fitting = false
    @State private var message: String?
    @State private var importing = false
    var body: some View {
        Form {
            EngramListSection {
                Text("Fitting uses accepted, mapped, explicitly unassisted outcomes from this library. Numerical eligibility is not proof of learning benefit.").font(.subheadline)
                ForEach([LearnerModelID.das3h, .bkt, .dynamicRasch], id: \.rawValue) { id in
                    Button("Fit " + id.rawValue) {
                        fitting = true
                        Task {
                            defer { fitting = false }
                            do { let report = try await model.service.fitPersonalLearnerModel(id); message = report.eligibleForReview ? "Candidate ready for validation review." : "Candidate did not pass calibration gates."; await model.understanding.refresh(model) }
                            catch { message = "Insufficient compatible evidence or unsupported fit: " + error.localizedDescription }
                        }
                    }.disabled(fitting || !(model.understanding.status?.recordingEnabled ?? false))
                }
                Text("DINA fitting requires a supported assessment and permitted held-out learners. Import its reviewed cohort artifact through the local fitting interface.").font(.caption).engramSecondaryText()
                Button("Import local fitting candidate") { importing = true }
            }
            if let status = model.understanding.status {
                ForEach(status.calibrationReports, id: \.id) { report in
                    EngramListSection {
                        Text(report.model.rawValue).font(.headline)
                        Text("\(report.trainingAttempts) training · \(report.validationAttempts) held out").font(.subheadline)
                        Text("Log loss \(report.logLoss.formatted()) · baseline \(report.baselineLogLoss.formatted())").font(.caption)
                        Text(report.eligibleForReview ? "Eligible for validation review" : "Not eligible").font(.caption)
                        if report.eligibleForReview {
                            Button("Run automated report check") {
                                fitting = true
                                Task {
                                    defer { fitting = false }
                                    do { try await model.understanding.reviewCandidate(report, model: model); message = "Report checked. Choose Observe or Active in Advanced models; this is not evidence of learning superiority." }
                                    catch { message = error.localizedDescription }
                                }
                            }.disabled(fitting || !model.aiMarker.enabled)
                        }
                    }
                }
            }
            if let message { EngramListSection { Text(message).font(.caption) } }
        }.modifier(UtilityListStyle()).navigationTitle("Fitting evidence")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                Task {
                    do {
                        let url = try result.get(), accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 20000000 else { throw LearnerError.invalidEvidence }
                        let report = try await model.service.importLearnerCalibrationCandidate(Data(contentsOf: url))
                        message = "Imported \(report.model.rawValue) candidate without activation."; await model.understanding.refresh(model)
                    } catch { message = error.localizedDescription }
                }
            }
    }
}
