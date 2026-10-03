import SwiftUI
import LearningCore
import DesignSystem

struct MultipleChoiceReviewView: View {
    @Bindable var model: EngramModel
    let originalQuestion: MultipleChoiceQuestion
    let item: ReviewPresentation
    let viewportSize: CGSize
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize

    init(model: EngramModel, question: MultipleChoiceQuestion, item: ReviewPresentation, viewportSize: CGSize) {
        self.model = model; self.originalQuestion = question; self.item = item; self.viewportSize = viewportSize
    }
    private var question: MultipleChoiceQuestion { originalQuestion.ordered(for: item.presentationID) }
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var selected: String? {
        get { model.reviewChoiceSelection?.presentationID == item.presentationID ? model.reviewChoiceSelection?.choiceID : nil }
        nonmutating set { model.reviewChoiceSelection = newValue.map { (item.presentationID, $0) } }
    }
    private var splitLayout: Bool { viewportSize.width >= 600 && viewportSize.width > viewportSize.height * 1.15 && !textSize.isAccessibilitySize }

    var body: some View {
        Group {
            if splitLayout {
                HStack(spacing: 40) {
                    ScrollView {
                        prompt.frame(maxWidth: .infinity, minHeight: max(120, viewportSize.height - 32))
                            .padding(.vertical, 16)
                    }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("review-question-pane")
                    ScrollView {
                        choices.frame(maxWidth: .infinity, minHeight: max(120, viewportSize.height - 32))
                            .padding(.vertical, 16)
                    }.scrollBounceBehavior(.basedOnSize).accessibilityIdentifier("review-options-pane")
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 1100).frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 36) {
                        prompt.frame(maxWidth: 560)
                        choices.frame(maxWidth: 500)
                    }
                    .frame(maxWidth: .infinity, minHeight: max(160, viewportSize.height - 32))
                    .padding(.vertical, 16)
                    .padding(.horizontal, textSize.isAccessibilitySize ? 20 : 36)
                }.scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("review-mcq-stacked")
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.84), value: item.assessment != nil)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.success, trigger: item.assessment?.outcome == .correct)
    }

    private var prompt: some View {
        Text(question.prompt)
            .font(theme.font(question.prompt.count < 160 ? .prompt : .body))
            .fontWeight(question.prompt.count < 160 ? .medium : .regular)
            .foregroundStyle(palette.primaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("review-question")
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(question.choices) { choice in choiceRow(choice) }
        }
    }

    private func choiceRow(_ choice: MultipleChoiceQuestion.Choice) -> some View {
        let submitted = item.assessment?.choiceID
        let correct = item.assessment != nil && choice.id == question.correctID
        let wrong = submitted == choice.id && !correct
        let active = item.assessment == nil && selected == choice.id
        let ink = correct ? palette.successInk : wrong ? palette.againInk : active ? palette.answerSelectionInk : palette.primaryText
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard item.assessment == nil, item.revealedAt == nil, !model.busy, !model.markingAnswer else { return }
                if selected == choice.id { confirm(choice.id) }
                else { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { selected = choice.id } }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(question.displayLetter(for: choice.id) + ".")
                        .font(.subheadline.weight(.semibold)).frame(width: 22, alignment: .leading)
                    Text(choice.text).font(.body.italic()).frame(maxWidth: .infinity, alignment: .leading)
                    if correct { Image(systemName:"checkmark").accessibilityHidden(true) }
                    else if wrong { Image(systemName:"xmark").accessibilityHidden(true) }
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(item.assessment == nil && item.revealedAt == nil && !model.busy && !model.markingAnswer)
            .accessibilityIdentifier("review-option-" + choice.id)
            .accessibilityLabel("Option \(question.displayLetter(for: choice.id)), \(choice.text)")
            .accessibilityValue(correct ? "Correct answer" : wrong ? "Your answer, incorrect" : active ? "Selected" : "Not selected")
            .accessibilityHint(item.assessment == nil ? "Select an answer, then confirm the selected answer." : "")
            .accessibilityAction(named: Text("Confirm answer")) { if item.assessment == nil { confirm(choice.id) } }
            if correct {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.assessment?.outcome == .correct ? "Correct" : "Correct answer")
                        .font(.caption.weight(.semibold)).foregroundStyle(palette.successInk)
                    Text(explanationDetail)
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("review-explanation")
                }
                .padding(.leading, 36).padding(.bottom, 14)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
            if choice.id != question.choices.last?.id {
                Rectangle().fill(palette.hairline).frame(height: 1).padding(.leading, 36)
            }
        }
    }

    private var explanationDetail: String {
        let full = question.displayedExplanation
        let prefix = question.displayLetter(for: question.correctID) + ")"
        guard full.hasPrefix(prefix) else { return full }
        var detail = String(full.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        if let correct = question.choices.first(where: { $0.id == question.correctID }),
           detail.lowercased().hasPrefix(correct.text.lowercased()) {
            detail = String(detail.dropFirst(correct.text.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: ".:;–—- ").union(.whitespacesAndNewlines))
        }
        return detail.isEmpty ? String(full.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) : detail
    }
    private func confirm(_ id: String) { Task { await model.submitChoice(id, presentationID: item.presentationID) } }
}
