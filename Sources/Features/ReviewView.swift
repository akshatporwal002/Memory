import SwiftUI
import LearningCore
import DesignSystem

struct ReviewView: View {
    @Bindable var model: EngramModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var answerFocused: Bool
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if let error = model.error { EngramInlineError(message: error).padding(EngramSpacing.regular) }
                    if let session = model.library.session, let item = session.current,
                       let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                                HStack {
                                    Text(model.deckName(note.deckID)).font(theme.font(.metadata))
                                    Spacer()
                                    Text("\(session.completed) saved · \(session.queue.count) ready").font(theme.font(.metadata)).monospacedDigit()
                                }.foregroundStyle(theme.palette(for: scheme).secondaryText)
                                reviewContent(note: note, item: item)
                            }
                            .frame(maxWidth: EngramShape.readingWidth).padding(EngramSpacing.section).frame(maxWidth: .infinity)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            controls(session: session, item: item, width: geometry.size.width)
                                .padding(EngramSpacing.regular).frame(maxWidth: .infinity)
                                .background(theme.palette(for: scheme).canvas)
                        }
                    } else { completion }
                }
            }
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Exit review") { dismiss() }.keyboardShortcut(.escape, modifiers: []).disabled(model.busy) }
                ToolbarItem(placement: .automatic) {
                    Button { Task { await model.undo() } } label: { Label("Undo last grade", systemImage: "arrow.uturn.backward") }
                        .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo || model.busy)
                }
            }
            .engramCanvas()
            .onChange(of: model.library.session?.current?.revealedAt) { _, newValue in if newValue != nil { answerFocused = true } }
        }
        .frame(minWidth: 300, idealWidth: 820, minHeight: 550)
        .interactiveDismissDisabled(model.busy)
    }
    @ViewBuilder private func reviewContent(note: Note, item: ReviewPresentation) -> some View {
        let rendered = Result { try CardRenderer.render(note: note, card: item.card, revealed: item.revealedAt != nil) }
        switch rendered {
        case .success(let card):
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                Text("QUESTION").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                CardContentView(text: card.prompt, media: model.library.media)
                    .font(theme.font(card.prompt.count < 160 ? .prompt : .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let answer = card.answer {
                    Divider()
                    Text("ANSWER").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                        .accessibilityFocused($answerFocused)
                    CardContentView(text: answer, media: model.library.media).font(theme.font(.body))
                        .transition(EngramMotion.contentTransition(reduceMotion: reduceMotion))
                    if let source = card.source, !source.isEmpty {
                        Text("Reference: \(source)").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText).textSelection(.enabled)
                    }
                } else {
                    Text("Take a moment to recall.").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 280, alignment: .leading)
            .engramSurface()
            .animation(EngramMotion.reveal(reduceMotion: reduceMotion), value: item.revealedAt)
        case .failure(let error): EngramInlineError(message: error.localizedDescription)
        }
    }
    @ViewBuilder private func controls(session: StudySession, item: ReviewPresentation, width: CGFloat) -> some View {
        VStack(spacing: EngramSpacing.small) {
            if item.revealedAt == nil {
                EngramActionButton("Reveal answer", busy: model.busy) {
                    Task { await model.reveal(sessionID: session.id, presentationID: item.presentationID) }
                }.keyboardShortcut(.space, modifiers: [])
                Text("Space to reveal").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText)
            } else {
                Text("How well did you recall it?").font(theme.font(.metadata))
                let columns = textSize.isAccessibilitySize ? 1 : width < 600 ? 2 : 4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: EngramSpacing.small), count: columns), spacing: EngramSpacing.small) {
                    ForEach(Grade.allCases, id: \.rawValue) { grade in
                        EngramGradeButton(label: grade.label,
                            interval: interval(item.outcomes[grade]?.due, from: item.revealedAt ?? model.now),
                            tone: tone(grade)) {
                            Task { await model.grade(grade, sessionID: session.id, presentationID: item.presentationID) }
                        }
                        .keyboardShortcut(KeyEquivalent(Character(String(grade.rawValue))), modifiers: [])
                        .disabled(model.busy || item.outcomes[grade] == nil)
                    }
                }
            }
        }.frame(maxWidth: EngramShape.readingWidth)
    }
    private var completion: some View {
        ScrollView {
            VStack(spacing: EngramSpacing.section) {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(theme.palette(for: scheme).accentInk).accessibilityHidden(true)
                Text("A good place to pause.").font(theme.font(.hero)).multilineTextAlignment(.center)
                Text("You've finished the cards that are ready right now.").font(theme.font(.body)).multilineTextAlignment(.center)
                Text("\(model.library.session?.completed ?? 0) reviews saved in this session").font(theme.font(.section)).monospacedDigit()
                if let next = model.library.session?.nextLearningDue {
                    Text("A learning card is due \(next.formatted(date: .omitted, time: .shortened)). You can return then or check again.")
                        .font(theme.font(.body)).multilineTextAlignment(.center)
                }
                Button("Check for ready cards") { Task { _ = await model.perform { _ = try await $0.refreshSession(now: Date()) } } }
                    .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
                Button("Return to Today") { model.destination = .today; dismiss() }.buttonStyle(EngramButtonStyle())
                Text("Your progress is stored on this device.").font(theme.font(.metadata))
            }
            .frame(maxWidth: EngramShape.readingWidth).padding(EngramSpacing.generous).frame(maxWidth: .infinity)
        }
    }
    private func tone(_ grade: Grade) -> EngramGradeTone {
        switch grade { case .again: return .again; case .hard: return .hard; case .good: return .good; case .easy: return .easy }
    }
    private func interval(_ due: Date?, from: Date) -> String {
        guard let due else { return "Unavailable" }
        let seconds = max(0, due.timeIntervalSince(from))
        if seconds < 60 { return "Less than a minute" }
        if seconds < 3600 { let n = Int((seconds / 60).rounded()); return "\(n) \(n == 1 ? "minute" : "minutes")" }
        if seconds < 86400 { let n = Int((seconds / 3600).rounded()); return "\(n) \(n == 1 ? "hour" : "hours")" }
        let n = Int((seconds / 86400).rounded()); return "\(n) \(n == 1 ? "day" : "days")"
    }
}
