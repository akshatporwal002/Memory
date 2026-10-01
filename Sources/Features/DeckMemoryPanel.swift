import SwiftUI
import Charts
import LearningCore
import StudyApplication
import DesignSystem

struct DeckMemoryPanel: View {
    let model: EngramModel
    let deck: Deck
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var outlook: DeckMemoryOutlook?
    @State private var selectedCardID: String?
    @State private var editingTarget = false
    @State private var useCustomTarget = false
    @State private var target = 0.9

    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var curveColor: Color { scheme == .dark ? palette.easyInk : palette.anchor }
    private var selected: MemoryCardEstimate? { outlook?.cards.first { $0.id == selectedCardID } }
    private var values: [Double] { selected?.probabilities ?? outlook?.average ?? [] }
    private struct Point: Identifiable { let id: Int; let probability: Double }

    var body: some View {
        if let outlook {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Memory outlook").font(theme.font(.section))
                    Spacer()
                    Button { openTarget() } label: {
                        Text("Target \(Int((outlook.target * 100).rounded()))%")
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline).frame(minHeight: 44)
                }
                if outlook.cards.isEmpty {
                    Text("Review cards to see a recall curve. New and learning cards have no reliable estimate yet.")
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(values.first ?? 0, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                        Text(selected == nil ? "average estimated recall now" : "estimated recall now")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    Chart {
                        RuleMark(y: .value("Target", outlook.target * 100))
                            .foregroundStyle(palette.accentInk.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        ForEach(values.enumerated().map { Point(id: $0.offset, probability: $0.element) }) { point in
                            LineMark(x: .value("Day", point.id), y: .value("Recall", point.probability * 100))
                                .foregroundStyle(curveColor)
                                .interpolationMethod(.monotone)
                        }
                    }
                    .chartYScale(domain: 0.0...100.0)
                    .chartXAxis {
                        AxisMarks(values: [0, 7]) { value in AxisValueLabel { Text(value.as(Int.self) == 0 ? "Today" : "7 days") } }
                    }
                    .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) }
                    .frame(height: 150)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selectedCardID)
                    .accessibilityLabel("Estimated recall \(Int((values.first ?? 0) * 100)) percent today, against a \(Int(outlook.target * 100)) percent target; curve assumes no reviews for seven days")
                }
                if selected == nil {
                    VStack(alignment: .leading, spacing: 7) {
                        GeometryReader { geometry in
                            let total = max(1, outlook.aboveTarget + outlook.belowTarget + outlook.newCount + outlook.unavailableCount)
                            HStack(spacing: 0) {
                                curveColor.frame(width: geometry.size.width * CGFloat(outlook.aboveTarget) / CGFloat(total))
                                palette.accent.frame(width: geometry.size.width * CGFloat(outlook.belowTarget) / CGFloat(total))
                                palette.selection.frame(width: geometry.size.width * CGFloat(outlook.newCount) / CGFloat(total))
                                palette.hairline.frame(maxWidth: .infinity)
                            }.clipShape(RoundedRectangle(cornerRadius: 4))
                        }.frame(height: 10).accessibilityHidden(true)
                        Text("\(outlook.aboveTarget) above · \(outlook.belowTarget) below · \(outlook.newCount) new\(outlook.unavailableCount > 0 ? " · \(outlook.unavailableCount) unavailable" : "")")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    if !outlook.cards.isEmpty {
                        Menu {
                            ForEach(outlook.cards) { card in
                                Button(card.prompt) { selectedCardID = card.id }
                            }
                        } label: { Label("View individual cards", systemImage: "chevron.right") }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                } else {
                    Text(selected?.prompt ?? "").font(.subheadline).lineLimit(2)
                    Button("All cards") { selectedCardID = nil }.frame(minHeight: 44)
                }
                Text("FSRS estimates for studied cards. The curve assumes no further reviews; learning and unsupported cards are excluded from the average.")
                    .font(.caption).foregroundStyle(palette.secondaryText)
            }
            .padding(16)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .task(id: "\(model.library.revision)-\(deck.id)") {
                outlook = await model.service.memoryOutlook(for: deck, in: model.library, now: model.now)
            }
            .sheet(isPresented: $editingTarget) {
                NavigationStack {
                    Form {
                        Section {
                            Toggle("Custom target for this deck", isOn: $useCustomTarget)
                            if useCustomTarget {
                                HStack { Text("Desired retention"); Spacer(); Text(target, format: .percent.precision(.fractionLength(0))) }
                                Slider(value: $target, in: 0.8...0.97, step: 0.01)
                                    .accessibilityLabel("Desired retention")
                            }
                        } footer: {
                            Text("Higher retention schedules more reviews. This setting affects future reviews; it does not rewrite earlier results.")
                        }
                    }
                    .navigationTitle("Desired retention")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingTarget = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let value = useCustomTarget ? target : nil
                                editingTarget = false
                                Task { _ = await model.perform { try await $0.setDeckRetention(id: deck.id, desiredRetention: value) } }
                            }
                        }
                    }
                }.presentationDetents([.medium, .large])
            }
        } else {
            ProgressView("Calculating memory outlook…")
                .task(id: "\(model.library.revision)-\(deck.id)") {
                    outlook = await model.service.memoryOutlook(for: deck, in: model.library, now: model.now)
                }
        }
    }

    private func openTarget() {
        useCustomTarget = deck.desiredRetention != nil
        target = deck.desiredRetention ?? model.library.settings.desiredRetention
        editingTarget = true
    }
}
