import SwiftUI
import LearningCore

struct MultipleChoiceReviewView: View {
    @Bindable var model: EngramModel
    let question: MultipleChoiceQuestion
    let item: ReviewPresentation
    @State private var selected: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.prompt).font(.title3).fontWeight(.medium)
            ForEach(question.choices) { choice in
                let submitted = item.assessment?.choiceID
                let correct = item.assessment != nil && choice.id == question.correctID
                let wrong = submitted == choice.id && !correct
                let active = (submitted ?? selected) == choice.id
                let ink: Color = correct ? .green : (wrong ? .red : .primary)
                let fill: Color = correct ? .green : (wrong ? .red : (active ? .accentColor : .secondary))
                let border: Color = correct ? .green : (wrong ? .red : (active ? .accentColor : .secondary.opacity(0.25)))
                Button {
                    if selected == choice.id { confirm(choice.id) }
                    else { withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)) { selected = choice.id } }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(choice.id + ".").fontWeight(.semibold)
                        Text(choice.text).frame(maxWidth: .infinity, alignment: .leading)
                        if correct { Image(systemName: "checkmark.circle.fill") }
                        else if wrong { Image(systemName: "xmark.circle.fill") }
                        else if active { Image(systemName: "checkmark.circle") }
                    }.padding(16).frame(minHeight: 54)
                        .foregroundStyle(ink)
                        .background(fill.opacity(active || correct ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: active ? 2 : 1))
                        .scaleEffect(active && !reduceMotion ? 1.015 : 1)
                }.buttonStyle(.plain).disabled(item.revealedAt != nil || model.busy || model.markingAnswer)
                    .accessibilityLabel("Option \(choice.id), \(choice.text)")
                    .accessibilityValue(correct ? "Correct answer" : wrong ? "Your answer, incorrect" : active ? "Selected" : "Not selected")
                    .accessibilityHint("Tap to select. Tap the selected answer again to confirm.")
                    .accessibilityAction(named: Text("Confirm answer")) { if item.assessment == nil { confirm(choice.id) } }
            }
            if item.assessment == nil { Text(selected == nil ? "Choose an answer." : "Tap the selected answer again to confirm.").font(.caption).foregroundStyle(.secondary) }
            if let result = item.assessment {
                Label(result.outcome == .correct ? "Correct" : "Incorrect", systemImage: result.outcome == .correct ? "checkmark.circle.fill" : "xmark.circle.fill").font(.headline)
                Text(result.reason).transition(.opacity)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: item.assessment != nil)
            .sensoryFeedback(.selection, trigger: selected)
            .sensoryFeedback(.success, trigger: item.assessment?.outcome == .correct)
    }
    private func confirm(_ id: String) { Task { await model.submitChoice(id, presentationID: item.presentationID) } }
}
