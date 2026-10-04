import SwiftUI
import LearningCore
import DesignSystem

struct TypedAnswerView: View {
    @Bindable var model: EngramModel
    let item: ReviewPresentation
    var submitted: (AnswerAttempt) -> Void = { _ in }
    @State private var answer = ""
    @State private var mathAnswer = ""
    @State private var mathDocument = MathEntryDocument()
    @State private var mathematical = true
    @FocusState private var inputFocused: Bool
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var mode: MathInputMode { model.library.liveDecks.first { $0.id == item.card.deckID }?.mathInputMode ?? .off }
    private var mathQuestion: Bool { model.library.liveNotes.first { $0.id == item.card.noteID }?.acceptsMathInput == true && mode != .off }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if mathQuestion && mathematical {
                InlineMathKeyboard(answer: $mathAnswer, advanced: mode == .advanced, document: $mathDocument)
                Button("Use text instead", systemImage: "keyboard") { mathematical = false; inputFocused = true }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(palette.secondaryText)
            } else {
                TextField(inputFocused ? "" : "Type your response here", text: $answer, axis: .vertical)
                    .lineLimit(2...8).focused($inputFocused).textFieldStyle(.plain)
                    .font(theme.font(.body)).frame(minHeight: 70, alignment: .topLeading)
                    .accessibilityLabel("Your response").accessibilityIdentifier("typed-answer-input")
                Divider()
                if mathQuestion {
                    Button("Use maths keyboard", systemImage: "function") { inputFocused = false; mathematical = true }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(palette.secondaryText)
                }
            }
            EngramActionButton("Review answer", busy: model.deferredReview.busy) {
                inputFocused = false
                let response = mathQuestion && mathematical ? mathAnswer : answer
                Task { if let attempt = await model.deferredReview.submit(response, model: model, modality: mathQuestion && mathematical ? "math-keyboard" : "typed") { submitted(attempt); answer = ""; mathAnswer = ""; mathDocument = MathEntryDocument() } }
            }.disabled((mathQuestion && mathematical ? mathAnswer : answer).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("typed-answer-submit")
            if let error = model.deferredReview.error { Text(error).font(.caption).foregroundStyle(palette.againInk) }
        }.toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false } } }
        .onChange(of: item.presentationID) { _, _ in answer = ""; model.deferredReview.error = nil }
    }
}

struct SubmittedAnswerReveal: View {
    let attempt: AnswerAttempt
    var next: () -> Void
    @Environment(\.engramTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RichContentView(source: attempt.prompt).font(theme.font(.prompt))
                Text("Your response").font(.caption).engramSecondaryText()
                RichContentView(source: attempt.originalAnswer)
                Divider()
                Text("Reference answer").font(.caption).engramSecondaryText()
                RichContentView(source: attempt.expectedAnswer)
                EngramActionButton("Next question", action: next)
            }.padding(24)
        }.accessibilityIdentifier("submitted-answer-reveal")
    }
}

struct AnswerAnnotationView: View {
    let attempt: AnswerAttempt
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            annotated.textSelection(.enabled).lineSpacing(5)
            if !attempt.annotations.isEmpty { Text("Supported · Incorrect or irrelevant (struck through)").font(.caption).engramSecondaryText() }
            ForEach(Array(attempt.additions.enumerated()), id: \.offset) { _, addition in
                Text("Missing: " + addition.text).foregroundStyle(palette.againInk)
            }
        }
    }
    private var annotated: Text {
        let source = attempt.originalAnswer as NSString
        var result = Text(""), end = 0
        for span in attempt.validatedAnnotations(attempt.annotations) {
            if span.startUTF16 > end { result = result + Text(verbatim: source.substring(with: NSRange(location: end, length: span.startUTF16 - end))) }
            let segment = Text(verbatim: span.text)
            result = result + (span.kind == "correct" ? segment.foregroundColor(palette.successInk) : segment.strikethrough().foregroundColor(palette.againInk))
            end = span.startUTF16 + span.lengthUTF16
        }
        if end < source.length { result = result + Text(verbatim: source.substring(from: end)) }
        return result
    }
}
