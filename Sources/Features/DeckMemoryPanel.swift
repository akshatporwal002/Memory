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
    @State private var editingHorizon = false
    @State private var useExamDate = false
    @State private var examDate = Date()

    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var curveColor: Color { palette.curveInk }
    private var selected: MemoryCardEstimate? { outlook?.cards.first { $0.id == selectedCardID } }
    private var values: [Double] { selected?.probabilities ?? outlook?.average ?? [] }
    private var plannedDate: Date? {
        guard selected == nil, let date = outlook?.nextPlannedReview, let end = outlook?.sampleDates.last else { return nil }
        return date <= end ? max(model.now, date) : nil
    }
    private struct Point: Identifiable { let id: Int; let date: Date; let probability: Double }

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
                Button {
                    useExamDate = (deck.examDate ?? .distantPast) > model.now
                    examDate = useExamDate ? deck.examDate! : outlook.sampleDates.last ?? model.now
                    editingHorizon = true
                } label: {
                    HStack(spacing: 5) {
                        Text(useDeadline ? "Exam · " : "Until · ")
                        Text(outlook.sampleDates.last ?? model.now, format: .dateTime.month(.abbreviated).day().year())
                        Image(systemName: "chevron.down").font(.caption2)
                    }.font(.caption).foregroundStyle(palette.secondaryText).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("deck-forecast-horizon")
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
                        ForEach(selected?.history ?? outlook.history) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Recall", point.probability * 100), series: .value("Period", "Recorded reviews"))
                                .foregroundStyle(curveColor).lineStyle(StrokeStyle(lineWidth: 1.6))
                        }

                        RuleMark(y: .value("Target", outlook.target * 100))
                            .foregroundStyle(palette.accentInk.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        if let plannedDate {
                            RuleMark(x: .value("Planned review", plannedDate))
                                .foregroundStyle(palette.accentInk.opacity(0.65))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        }
                        ForEach(values.enumerated().map { Point(id: $0.offset, date: outlook.sampleDates[$0.offset], probability: $0.element) }) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Recall", point.probability * 100), series: .value("Period", "Forecast"))
                                .foregroundStyle(curveColor)
                                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
                                .interpolationMethod(.monotone)
                        }
                        PointMark(x:.value("Today",model.now),y:.value("Recall today",(values.first ?? 0) * 100))
                            .foregroundStyle(curveColor).symbolSize(64)
                    }
                    .chartYScale(domain: 0.0...100.0)
                    .chartXScale(domain: outlook.startDate...(outlook.sampleDates.last ?? model.now.addingTimeInterval(1)))
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading, values: [0, 50, 100]) }
                    .frame(height: 150)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selectedCardID)
                    .accessibilityLabel("Estimated recall \(Int((values.first ?? 0) * 100)) percent today, against a \(Int(outlook.target * 100)) percent target; dotted curve assumes no reviews until the displayed end date")
                    HStack { Text(outlook.startDate, format: .dateTime.month(.abbreviated).day().year()); Spacer(); Text(outlook.sampleDates.last ?? model.now, format: .dateTime.month(.abbreviated).day().year()) }
                        .font(.caption).foregroundStyle(palette.secondaryText).padding(.leading, 28)
                    if selected == nil,let next = outlook.nextPlannedReview {
                        HStack(alignment:.firstTextBaseline) {
                            Text(next <= model.now ? "Review due now" : "Next planned review · " + next.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength:8)
                            Text("\(outlook.scheduledWithinWeek) in 7 days")
                                .font(.caption).foregroundStyle(palette.secondaryText)
                        }
                    }
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
                Text("Solid line: available review history. Dotted line: recall from today if no reviews happen. The review marker shows a scheduled date, not a predicted increase. New and unsupported cards are excluded from the average.")
                    .font(.caption).foregroundStyle(palette.secondaryText)
            }
            .task(id: "\(model.library.revision)-\(deck.id)-\(Int(model.now.timeIntervalSince1970 / 60))") {
                self.outlook = await model.service.memoryOutlook(for: deck, in: model.library, now: model.now)
            }
            .sheet(isPresented: $editingHorizon) {
                NavigationStack {
                    Form {
                        Toggle("Exam or target date", isOn: $useExamDate)
                        if useExamDate {
                            DatePicker("Date", selection: $examDate, in: model.now..., displayedComponents: .date)
                        }
                        Text("Without a future target date, the graph runs from deck creation to one year from today. This changes the graph’s horizon, not your review schedule.")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    .navigationTitle("Memory outlook")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingHorizon = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let date = useExamDate ? (Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: examDate)) ?? examDate).addingTimeInterval(-1) : nil
                                editingHorizon = false
                                Task { _ = await model.perform { try await $0.setDeckExamDate(id: deck.id, date: date) } }
                            }
                        }
                    }
                }.presentationDetents([.medium, .large])
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
                .task(id: "\(model.library.revision)-\(deck.id)-\(Int(model.now.timeIntervalSince1970 / 60))") {
                    outlook = await model.service.memoryOutlook(for: deck, in: model.library, now: model.now)
                }
        }
    }

    private var useDeadline: Bool { (deck.examDate ?? .distantPast) > model.now }

    private func openTarget() {
        useCustomTarget = deck.desiredRetention != nil
        target = deck.desiredRetention ?? model.library.settings.desiredRetention
        editingTarget = true
    }
}
