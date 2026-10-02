import SwiftUI
import LearningCore
import DesignSystem

struct ReviewView: View {
    @Bindable var model: EngramModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var typing = false
    @AccessibilityFocusState private var answerFocused: Bool
    @State private var completionVisible = false
    @State private var optionsPresented = false
    var body: some View {
        EngramTaskContainer(embedded: embedded) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if let error = model.error { EngramInlineError(message: error).padding(EngramSpacing.regular) }
                    if model.voice.enabled { Text(model.voice.status).font(.caption).padding(8) }
                    if model.markingAnswer { ProgressView("Checking your answer…").padding(8) }
                    if let feedback = model.answerFeedback { Text(feedback).font(.subheadline).padding(8) }
                    if let session = model.library.session, let item = session.current,
                       let note = model.library.liveNotes.first(where: { $0.id == item.card.noteID }) {
                        VStack(spacing: 0) {
                            GeometryReader { viewport in
                                ScrollView {
                                    reviewContent(note: note, item: item,
                                        minimumHeight: max(160, viewport.size.height - 2 * EngramSpacing.regular - 2 * EngramSpacing.section))
                                        .id(item.presentationID)
                                        .frame(maxWidth: EngramShape.readingWidth)
                                        .padding(EngramSpacing.regular).frame(maxWidth: .infinity)
                                }
                            }
                            if !(typing && item.revealedAt == nil) && model.pendingAttempt?.assessment == nil {
                            controls(session: session, item: item, width: geometry.size.width)
                                .padding(EngramSpacing.regular).frame(maxWidth: .infinity)
                                .background(theme.palette(for: scheme).canvas)
                            }
                        }
                    } else { completion }
                }
            }
            .navigationTitle(reviewTitle)
            .engramInlineTitle().engramHideStudyTabs()
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: leaveReview) { Label("Back", systemImage: "chevron.left") }
                            .labelStyle(.iconOnly).keyboardShortcut(.escape, modifiers: []).disabled(model.busy)
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        if model.voice.ready { model.voice.enabled.toggle() }
                        else { optionsPresented = true }
                    } label: {
                        Label(model.voice.enabled ? "Stop voice mode" : "Start voice mode", systemImage: model.voice.enabled ? "mic.fill" : "mic")
                    }.accessibilityIdentifier("review-voice-mode")
                }
                ToolbarItem(placement: .automatic) {
                    Button { optionsPresented = true } label: { Label("Review options", systemImage: "ellipsis") }
                }
            }
            .onKeyPress(.escape) {
                guard !model.busy else { return .ignored }
                leaveReview(); return .handled
            }
            .onKeyPress(keys: ["z"], phases: .down) { key in
                guard key.modifiers.contains(.command), model.canUndo, !model.busy else { return .ignored }
                Task { await model.undo() }; return .handled
            }
            .engramCanvas()
            .sheet(isPresented: $optionsPresented) { reviewOptions }
            .onChange(of: model.library.session?.current?.revealedAt) { _, newValue in if newValue != nil { answerFocused = true } }
        }
        .modifier(EngramTaskSizing(embedded: embedded, width: 820, height: 550))
        .interactiveDismissDisabled(model.busy)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.library.session?.current?.presentationID)
        .onAppear { model.voice.present(model: model) }
        .onDisappear { model.voice.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.voice.stop() }
            else if phase == .active { model.voice.present(model: model) }
        }
        .onChange(of: model.voice.enabled) { _, _ in model.voice.present(model: model) }
        .onChange(of: model.library.session?.current?.presentationID) { _, _ in model.voice.present(model: model) }
        .onChange(of: model.library.session?.current?.revealedAt) { _, _ in model.voice.present(model: model) }
    }
    @ViewBuilder private func reviewContent(note: Note, item: ReviewPresentation, minimumHeight: CGFloat) -> some View {
        if let question = note.mcq {
            MultipleChoiceReviewView(model: model, question: question, item: item)
                .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading).engramSurface()
        } else {
        let rendered = Result { try CardRenderer.render(note: note, card: item.card, revealed: item.revealedAt != nil) }
        switch rendered {
        case .success(let card):
            VStack(alignment: .leading, spacing: EngramSpacing.section) {
                CardContentView(text: card.prompt, media: model.library.media)
                    .font(theme.font(card.prompt.count < 160 ? .prompt : .body))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain).accessibilityLabel("Question")
                if (typing && item.revealedAt == nil) || model.pendingAttempt?.assessment != nil {
                    TypedAnswerView(model:model,item:item)
                } else if item.revealedAt == nil {
                    Button("Type answer",systemImage:"keyboard") { typing = true }
                        .buttonStyle(EngramButtonStyle(.secondary))
                }
                if let answer = card.answer {
                    Divider()
                    CardContentView(text: answer, media: model.library.media).font(theme.font(.body))
                        .accessibilityElement(children: .contain).accessibilityLabel("Answer")
                        .accessibilityFocused($answerFocused)
                        .transition(EngramMotion.contentTransition(reduceMotion: reduceMotion))
                    if let source = card.source, !source.isEmpty {
                        Text("Reference: \(source)").font(theme.font(.metadata)).foregroundStyle(theme.palette(for: scheme).secondaryText).textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .engramSurface()
            .animation(EngramMotion.reveal(reduceMotion: reduceMotion), value: item.revealedAt)
        case .failure(let error): EngramInlineError(message: error.localizedDescription)
        }
        }
    }
    private var reviewTitle: String {
        guard let item = model.library.session?.current else { return "Review complete" }
        return model.deckName(item.card.deckID).components(separatedBy: "::").last ?? "Review"
    }
    private func leaveReview() { model.reviewPresented = false; dismiss() }

    private var reviewOptions: some View {
        NavigationStack {
            Form {
                Section("This session") {
                    LabeledContent("Reviews saved", value: String(model.library.session?.completed ?? 0))
                    LabeledContent("Cards ready", value: String(model.library.session?.queue.count ?? 0))
                    Button {
                        Task { await model.undo(); if model.error == nil { optionsPresented = false } }
                    } label: { Label("Undo last grade", systemImage: "arrow.uturn.backward") }
                        .keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo || model.busy)
                    if let error = model.error { EngramInlineError(message: error) }
                }
                Section("Voice") { VoiceModeSettings(voice: model.voice) }
                Section("Appearance") {
                    Picker("Theme", selection: model.themeSelection) {
                        ForEach(EngramTheme.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Appearance", selection: model.appearanceSelection) {
                        ForEach(EngramAppearance.allCases) { Text($0.title).tag($0) }
                    }
                }
            }
            .navigationTitle("Review options").engramInlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { optionsPresented = false } } }
            .engramCanvas()
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .engramSheetSizing(idealWidth: 440, minimumHeight: 360)
    }

    @ViewBuilder private func controls(session: StudySession, item: ReviewPresentation, width: CGFloat) -> some View {
        if model.pendingAttempt?.assessment != nil {
            EmptyView()
        } else if let assessment = item.assessment {
            VStack(spacing: 12) {
                Text(assessment.outcome.rawValue.capitalized + " · " + (assessment.rating?.label ?? "Ungraded")).font(.headline)
                if model.library.liveNotes.first(where: { $0.id == item.card.noteID })?.mcq == nil { Text(assessment.reason) }
                EngramActionButton("Next", busy: model.busy) { Task { await model.nextAnswer() } }
                Button("Undo assessment") { Task { await model.undo() } }.disabled(model.busy)
            }
        } else if model.library.liveNotes.first(where: { $0.id == item.card.noteID })?.mcq != nil {
            Text("Tap an option twice to confirm, or speak its letter or answer.").font(.caption)
        } else {
        // Reserve the actual grade controls' height before reveal so the reading surface stays still.
        ZStack(alignment: .bottom) {
            VStack(spacing: EngramSpacing.small) {
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
                        .disabled(item.revealedAt == nil || model.busy || item.outcomes[grade] == nil)
                    }
                }
            }
            .opacity(item.revealedAt == nil ? 0 : 1)
            .accessibilityHidden(item.revealedAt == nil)
            .allowsHitTesting(item.revealedAt != nil)
            if item.revealedAt == nil {
                EngramActionButton("Reveal answer", busy: model.busy) {
                    Task { await model.reveal(sessionID: session.id, presentationID: item.presentationID) }
                }.keyboardShortcut(.space, modifiers: [])
            }
        }.frame(maxWidth: EngramShape.readingWidth)
        }
    }
    private var completion: some View {
        ScrollView {
            VStack(spacing: EngramSpacing.section) {
                VStack(spacing: EngramSpacing.section) {
                    Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(theme.palette(for: scheme).accentInk).accessibilityHidden(true)
                        .scaleEffect(reduceMotion || completionVisible ? 1 : 0.94)
                    Text("A good place to pause.").font(theme.font(.hero)).multilineTextAlignment(.center)
                    Text("You've finished the cards that are ready right now.").font(theme.font(.body)).multilineTextAlignment(.center)
                    Text("\(model.library.session?.completed ?? 0) reviews saved in this session").font(theme.font(.section)).monospacedDigit()
                        .engramNumericTransition(value: model.library.session?.completed ?? 0)
                }
                .opacity(completionVisible ? 1 : 0)
                .offset(y: reduceMotion || completionVisible ? 0 : 8)
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
            .onAppear {
                guard let id = model.library.session?.id, !model.animatedCompletionSessions.contains(id) else {
                    completionVisible = true; return
                }
                model.animatedCompletionSessions.insert(id)
                withAnimation(EngramMotion.completion(reduceMotion: reduceMotion)) { completionVisible = true }
            }
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
