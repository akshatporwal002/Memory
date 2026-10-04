import SwiftUI
import LearningCore
import DesignSystem

struct TypedAnswerView: View {
    @Bindable var model: EngramModel
    let item: ReviewPresentation
    @State private var answer = ""
    @State private var discussion = ""
    @State private var discussing = false
    @State private var accepting = false
    @State private var equationPresented = false
    @FocusState private var inputFocused: Bool
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: EngramPalette { theme.palette(for:scheme) }
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if let attempt = model.pendingAttempt,let assessment = attempt.assessment {
                Text("Your answer").font(.headline)
                AnswerAnnotationView(attempt:attempt)
                HStack { Text(assessment.outcome.rawValue.capitalized).font(.headline); Spacer(); Text("Provisional · " + (assessment.rating?.label ?? "Ungraded")).font(.caption).engramSecondaryText() }
                RichContentView(source:assessment.reason)
                if !attempt.additions.isEmpty {
                    Text("Missing information").font(.caption.weight(.semibold))
                    ForEach(Array(attempt.additions.enumerated()),id:\.offset) { _,addition in
                        AnimatedAddition(text:addition.text).foregroundStyle(palette.missingInk)
                    }
                }
                DisclosureGroup("Supporting evidence") {
                    ForEach(attempt.evidence) { evidence in
                        VStack(alignment:.leading,spacing:5) { Text(evidence.id).font(.caption.weight(.semibold)); Text(evidence.text).font(.subheadline).textSelection(.enabled) }
                    }
                }
                Button("Discuss feedback") { discussing.toggle() }
                if discussing {
                    TextField("What should the assessment reconsider?",text:$discussion,axis:.vertical).textFieldStyle(.roundedBorder)
                    Button("Reconsider original answer") { Task { await model.typedAnswer.discuss(discussion,attempt:attempt,model:model); discussion = "" } }.disabled(model.typedAnswer.busy || discussion.isEmpty)
                    if let conversation = model.library.assistantState?.conversations.first(where: { $0.id == "grading:" + attempt.id }) {
                        ForEach(conversation.messages) { message in
                            VStack(alignment:.leading,spacing:4) { Text(message.role == "user" ? "You" : "Assistant").font(.caption.weight(.semibold)); RichContentView(source:message.text) }
                        }
                    }
                }
                if let proposed = assessment.proposedAnswer,proposed != attempt.expectedAnswer {
                    Button("Update card answer…") { accepting = true }
                        .sheet(isPresented:$accepting) {
                            NavigationStack { ScrollView { VStack(alignment:.leading,spacing:16) {
                                Text("Current answer").font(.headline); RichContentView(source:attempt.expectedAnswer)
                                Divider(); Text("Proposed improvement").font(.headline); RichContentView(source:proposed)
                                Text("Accepting queues this improvement. Next saves your original recall grade and the accepted card update together.").font(.caption).engramSecondaryText()
                                Button("Accept improvement") { Task { await model.typedAnswer.acceptImprovement(proposed,attempt:attempt,model:model); if model.typedAnswer.error == nil { accepting = false } } }.buttonStyle(EngramButtonStyle())
                                if let error = model.typedAnswer.error { EngramInlineError(message:error) }
                            }.padding(20) }.navigationTitle("Improve answer").toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { accepting = false } } } }
                        }
                }
                Button("Remember this correction") { Task {
                    _ = await model.perform { try await $0.saveLearningMemory(LearningMemory(id:"correction-" + attempt.id,noteID:attempt.noteID,text:assessment.reason,evidenceIDs:assessment.evidenceIDs ?? [])) }
                }}
                if assessment.rating != nil,!attempt.assisted {
                    EngramActionButton("Next",busy:model.busy || model.typedAnswer.busy) {
                        Task { _ = await model.perform { try await $0.commitAnswerAttempt(id:attempt.id,providerAccountID:model.aiMarker.commitIdentity(for:attempt, connection:model.chatGPT)) } }
                    }.accessibilityIdentifier("typed-answer-next")
                }
                Menu("Rate manually instead") {
                    ForEach(Grade.allCases,id:\.rawValue) { grade in
                        Button(grade.label) { Task { _ = await model.perform { try await $0.commitAnswerAttempt(id:attempt.id,manualGrade:grade) } } }
                    }
                }
            } else {
                TextField("Type your answer",text:$answer,axis:.vertical).lineLimit(3...8)
                    .focused($inputFocused)
                    .padding(12).background(palette.surface,in:RoundedRectangle(cornerRadius:12))
                    .accessibilityIdentifier("typed-answer-input")
                Button("Equation", systemImage: "function") { inputFocused = false; equationPresented = true }
                    .buttonStyle(.plain).font(.subheadline).foregroundStyle(palette.accentInk)
                    .accessibilityIdentifier("typed-answer-equation")
                    .sheet(isPresented: $equationPresented) {
                        MathEntryView { source in answer += (answer.isEmpty ? "" : " ") + source }
                    }
                EngramActionButton("Review answer",busy:model.typedAnswer.busy) {
                    inputFocused = false; Task { await model.typedAnswer.assess(answer,model:model) }
                }.disabled(answer.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if let error = model.typedAnswer.error { EngramInlineError(message:error) }
            if model.typedAnswer.busy { ProgressView("Reviewing…") }
        }.toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("Done") { inputFocused = false } } }
        .onChange(of:item.presentationID) { _,_ in answer = ""; discussion = ""; discussing = false; model.typedAnswer.error = nil }
    }
}

private struct AnswerAnnotationView: View {
    let attempt: AnswerAttempt
    @State private var colored = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var palette: EngramPalette { theme.palette(for:scheme) }
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            annotated.textSelection(.enabled).lineSpacing(5)
            if !attempt.annotations.isEmpty { Text("Green: supported · Struck out: incorrect or irrelevant").font(.caption).engramSecondaryText() }
        }.task(id:attempt.assessment?.reason) {
            colored = false
            if reduceMotion { colored = true }
            else { withAnimation(.easeInOut(duration:0.45)) { colored = true } }
        }
    }
    private var annotated: Text {
        let source = attempt.originalAnswer as NSString
        var result = Text(""),end = 0
        for span in attempt.validatedAnnotations(attempt.annotations) {
            if span.startUTF16 > end { result = result + Text(verbatim:source.substring(with:NSRange(location:end,length:span.startUTF16-end))) }
            let segment = Text(verbatim:span.text)
            if span.kind == "correct" { result = result + segment.foregroundColor(colored ? palette.successInk : palette.primaryText) }
            else { result = result + segment.strikethrough(colored).foregroundColor(colored ? palette.againInk : palette.primaryText) }
            end = span.startUTF16 + span.lengthUTF16
        }
        if end < source.length { result = result + Text(verbatim:source.substring(from:end)) }
        return result
    }
}
private struct AnimatedAddition: View {
    let text: String
    @State private var count = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Text(String(text.prefix(count))).accessibilityLabel("Missing: " + text)
            .task(id:text) {
                if reduceMotion { count = text.count; return }
                count = 0
                let step = max(1,text.count / 60)
                while count < text.count,!Task.isCancelled {
                    count = min(text.count,count + step)
                    do { try await Task.sleep(for:.milliseconds(18)) } catch { return }
                }
            }
    }
}
