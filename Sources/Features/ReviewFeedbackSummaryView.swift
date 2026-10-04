import SwiftUI
import LearningCore
import DesignSystem

struct ReviewFeedbackSummaryView: View {
    @Bindable var model: EngramModel
    @State private var ids: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    private var attempts: [AnswerAttempt] { (model.library.answerAttempts ?? []).filter { ids.contains($0.id) }.sorted { $0.createdAt < $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 20) {
                    ForEach(Grade.allCases, id: \.rawValue) { grade in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(attempts.filter { effectiveGrade($0) == grade }.count)).font(theme.font(.section))
                            Text(grade.label).font(.caption).engramSecondaryText()
                        }
                    }
                    Spacer()
                    Text("\(attempts.filter { $0.committedAt == nil }.count) to review").font(.caption).engramSecondaryText()
                }
                ForEach(attempts) { attempt in
                    Divider()
                    AttemptFeedbackRow(model: model, attempt: attempt)
                }
            }.padding(24).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.navigationTitle("Review feedback").engramInlineTitle().engramCanvas()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            let saved = model.deferredReview.summaryIncludesViewed ? (model.library.answerAttempts ?? []).filter { $0.deferredCard != nil && ["finished", "attention", "failed"].contains($0.processingState ?? "") } : model.deferredReview.unseen(model)
            ids = Set(saved.map(\.id))
        }
        .onDisappear { let viewed = ids; Task { _ = await model.perform { try await $0.markFeedbackViewed(ids: viewed) } } }
    }
    private func effectiveGrade(_ attempt: AnswerAttempt) -> Grade? {
        guard attempt.committedAt != nil else { return nil }
        return model.library.activeReviews.last { $0.cardID == attempt.cardID && $0.sessionID == attempt.sessionID && $0.reviewedAt == attempt.createdAt }?.rating
    }
}

private struct AttemptFeedbackRow: View {
    @Bindable var model: EngramModel
    let attempt: AnswerAttempt
    @State private var dispute = ""
    @State private var discussing = false
    @State private var selectedEvidence: AttemptEvidence?
    @Environment(\.engramTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RichContentView(source: attempt.prompt).font(theme.font(.section))
            AnswerAnnotationView(attempt: attempt)
            HStack {
                Text(attempt.committedAt == nil ? "Manual review needed" : model.library.activeReviews.last { $0.cardID == attempt.cardID && $0.sessionID == attempt.sessionID && $0.reviewedAt == attempt.createdAt }?.rating.label ?? "Reviewed").font(.caption.weight(.medium))
                Spacer(); Text(attempt.createdAt, style: .date).font(.caption).engramSecondaryText()
            }
            if let assessment = attempt.assessment {
                RichContentView(source: citedReason(assessment))
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "engram-citation", let number = Int(url.host ?? ""),
                              let ids = assessment.evidenceIDs, ids.indices.contains(number - 1),
                              let evidence = attempt.evidence.first(where: { $0.id == ids[number - 1] }) else { return .systemAction }
                        selectedEvidence = evidence; return .handled
                    })
            }
            if let error = attempt.processingError { Text(error).font(.caption).engramErrorText() }
            if attempt.committedAt == nil {
                if attempt.processingState == "failed" {
                    Button("Retry marking") { Task {
                        _ = await model.perform { try await $0.retryDeferredAnswer(id: attempt.id, providerAccountID: model.aiMarker.gradingIdentity(model.chatGPT)) }
                        model.deferredReview.requestFlush()
                    } }.buttonStyle(.plain)
                }
                Menu("Rate manually") {
                    ForEach(Grade.allCases, id: \.rawValue) { grade in
                        Button(grade.label) { Task { _ = await model.perform { try await $0.finishDeferredAnswer(id: attempt.id, assessment: attempt.assessment, providerAccountID: attempt.providerAccountID, manualGrade: grade) } } }
                    }
                }.buttonStyle(.plain)
            }
            Button("Dispute feedback", systemImage: "bubble.left") { discussing.toggle() }.buttonStyle(.plain).font(.subheadline)
            if discussing {
                TextField("What should be reconsidered?", text: $dispute, axis: .vertical).textFieldStyle(.plain).lineLimit(2...6)
                Divider()
                Button("Reconsider original answer") { Task { await model.typedAnswer.discuss(dispute, attempt: attempt, model: model); dispute = "" } }
                    .disabled(dispute.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.typedAnswer.busy)
                if model.typedAnswer.busy { ProgressView() }
                if let error = model.typedAnswer.error { Text(error).font(.caption).engramErrorText() }
            }
        }
        .sheet(item: $selectedEvidence) { evidence in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Source excerpt").font(theme.font(.section))
                        Text(EvidenceExcerpt.relevantText(evidence.text, question: attempt.prompt, claim: attempt.assessment?.reason ?? ""))
                            .textSelection(.enabled).font(.body).lineSpacing(5)
                    }.padding(24)
                }.engramCanvas().navigationTitle("Citation").engramInlineTitle()
            }
        }
    }
    private func citedReason(_ assessment: AnswerAssessment) -> String {
        var reason = assessment.reason
        for index in (assessment.evidenceIDs ?? []).indices.reversed() {
            let label = "[\(index + 1)]", link = "[\(index + 1)](engram-citation://\(index + 1))"
            if reason.contains(label) { reason = reason.replacingOccurrences(of: label, with: link) }
            else { reason += " " + link }
        }
        return reason
    }
}
