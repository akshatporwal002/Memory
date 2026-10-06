import SwiftUI
import LearningCore
import DesignSystem

/// Separate understanding attempts, using the notebook's existing reading typography.
struct UnderstandingPracticeView: View {
    @Bindable var model: EngramModel
    @State private var answer = ""
    @State private var assisted = false
    @State private var activeSeconds: Double = 0
    @State private var started: Date?
    @State private var correctionID: String?
    @State private var correctionReason = ""
    @State private var confirmingFinish = false
    @State private var shownAttemptID: String?
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let session = model.understanding.current {
                        if let attempt = session.current {
                            CardContentView(text: attempt.variant.front, media: model.library.media).font(.body.weight(.bold))
                            if let mcq = MultipleChoiceQuestion.parse(front: attempt.variant.front, back: attempt.variant.back) {
                                ForEach(mcq.choices) { choice in
                                    Button { answer = choice.id + ") " + choice.text } label: {
                                        HStack { Text(choice.id + ") " + choice.text); Spacer(); if answer == choice.id + ") " + choice.text { Image(systemName: "checkmark") } }
                                    }.buttonStyle(.plain)
                                }
                            } else {
                                TextEditor(text: $answer).frame(minHeight: 160).accessibilityLabel("Your answer")
                            }
                            Toggle("I used help or viewed the answer", isOn: $assisted).font(.subheadline)
                            if !model.understanding.predictions.isEmpty {
                                DisclosureGroup("Model predictions") {
                                    ForEach([LearnerPurpose.skill, .difficulty, .diagnosis], id: \.rawValue) { purpose in
                                        if let prediction = model.understanding.predictions[purpose] {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(prediction.model.rawValue).font(.subheadline)
                                                if let probability = prediction.probabilityCorrect { Text("Predicted correct: " + probability.formatted(.percent)).font(.caption) }
                                                if let ability = prediction.abilityMean { Text("Conditional ability estimate: " + ability.formatted()).font(.caption) }
                                                if let lower = prediction.abilityLower, let upper = prediction.abilityUpper { Text("Conditional 95% interval: \(lower.formatted())–\(upper.formatted())").font(.caption) }
                                                Text("Model estimate, not an observed result.").font(.caption).engramSecondaryText()
                                            }
                                        }
                                    }
                                }.font(.caption)
                            }
                            Button("Submit and continue") {
                                pauseTimer()
                                Task { await model.understanding.submit(answer: answer, assisted: assisted, seconds: activeSeconds, model: model) }
                            }.buttonStyle(EngramButtonStyle()).disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.understanding.busy)
                            if let quick = session.attempts.last(where: { $0.status != .presented })?.provisional {
                                Text("Provisional: " + quick.label).font(.caption).engramSecondaryText()
                            }
                        } else {
                            Text("Session review").font(.title2.weight(.semibold))
                            Text("Deeper assessments update here as they finish.").font(.subheadline).engramSecondaryText()
                            ForEach(session.attempts.filter { $0.status != .abandoned }) { attempt in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(attempt.variant.front).font(.body.weight(.bold))
                                    Text(attempt.answer).font(.subheadline)
                                    if let provisional = attempt.provisional { Text("Provisional: " + provisional.label).font(.caption).engramSecondaryText() }
                                    if let assessment = attempt.assessment {
                                        Text((attempt.status == .queued ? "Previous final: " : "Final: ") + (assessment.rating?.label ?? "Needs review")).font(.subheadline.weight(.semibold))
                                        if attempt.status == .queued { Text("Reassessment pending").font(.caption).engramSecondaryText() }
                                        Text(assessment.reason).font(.subheadline)
                                        DisclosureGroup("Reference answer") { Text(attempt.variant.back).font(.subheadline) }
                                    } else { Text(attempt.status == .attention ? "Needs attention" : "Pending assessment").font(.subheadline).engramSecondaryText() }
                                    if let error = attempt.error { Text(error).font(.caption).engramSecondaryText() }
                                    Button(attempt.assessment == nil ? "Retry assessment" : "Request assessment correction") {
                                        correctionID = attempt.id; correctionReason = ""
                                    }.font(.caption).disabled(model.understanding.processing || attempt.status == .queued)
                                    Divider()
                                }
                            }
                        }
                    }
                    if let error = model.understanding.error { Text(error).font(.caption).engramSecondaryText() }
                }.padding(EngramSpacing.section).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.engramCanvas().navigationTitle("Understanding practice").engramInlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            pauseTimer()
                            Task { if await saveDraft() { dismiss() } }
                        }
                    }
                    if model.understanding.current?.current != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Finish") {
                                pauseTimer()
                                if answer.isEmpty { finish() } else { confirmingFinish = true }
                            }
                        }
                    }
                }
        }
        .onAppear {
            if let attempt = model.understanding.current?.current {
                shownAttemptID = attempt.id; answer = attempt.answer; assisted = attempt.assisted ?? false; activeSeconds = attempt.activeSeconds ?? 0
                if phase == .active { started = Date() }
            }
        }
        .interactiveDismissDisabled(!answer.isEmpty && model.understanding.current?.current != nil)
        .confirmationDialog("Finish without submitting this answer?", isPresented: $confirmingFinish) {
            Button("Finish without submitting") { finish() }
            Button("Keep practising", role: .cancel) { if phase == .active { started = Date() } }
        }
        .alert("Request assessment review", isPresented: Binding(get: { correctionID != nil }, set: { if !$0 { correctionID = nil } })) {
            TextField("What should be reconsidered? (optional)", text: $correctionReason)
            Button("Queue review") {
                if let id = correctionID {
                    Task {
                        do { try await model.service.retryUnderstandingAssessment(attemptID: id, providerIdentity: model.aiMarker.gradingIdentity(model.chatGPT), gradingModel: model.aiMarker.selectedModel, reason: correctionReason); await model.understanding.refresh(model) }
                        catch { model.understanding.error = error.localizedDescription }
                    }
                }
                correctionID = nil
            }
            Button("Cancel", role: .cancel) { correctionID = nil }
        }
        .onDisappear { pauseTimer() }
        .onChange(of: model.understanding.current?.current?.id) { _, id in
            shownAttemptID = id
            answer = ""; assisted = false; activeSeconds = 0; started = id != nil && phase == .active ? Date() : nil
        }
        .onChange(of: model.understanding.busy) { _, busy in
            if !busy && model.understanding.current?.current != nil && started == nil && phase == .active { started = Date() }
        }
        .onChange(of: phase) { _, phase in
            if phase == .active && model.understanding.current?.current != nil { started = Date() } else { pauseTimer(); Task { _ = await saveDraft() } }
        }
    }
    private func pauseTimer() {
        if let started { activeSeconds += max(0, Date().timeIntervalSince(started)); self.started = nil }
    }
    private func saveDraft() async -> Bool {
        guard let session = model.understanding.current, let attempt = session.current, attempt.id == shownAttemptID else { return true }
        do {
            try await model.service.saveUnderstandingDraft(sessionID: session.id, attemptID: attempt.id, answer: answer, assisted: assisted,
                activeSeconds: activeSeconds, expectedAccount: model.understanding.account(model), expectedLibrary: model.activeLibraryID)
            await model.understanding.refresh(model); return true
        } catch { model.understanding.error = error.localizedDescription; return false }
    }
    private func finish() {
        Task {
            guard await saveDraft() else { return }
            do { if let id = model.understanding.currentID { try await model.service.endUnderstandingSession(id: id) }; await model.understanding.refresh(model) }
            catch { model.understanding.error = error.localizedDescription }
        }
    }
}
