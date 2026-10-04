import SwiftUI
import Charts
import LearningCore
import StudyApplication
import DesignSystem

struct DeckMemoryPanel: View {
    let model: EngramModel
    let deck: Deck
    @Environment(\.engramWorkspaceLayout) private var workspace
    private var chartHeight: CGFloat { workspace ? 260 : 180 }
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var outlook: DeckMemoryOutlook?
    @State private var selectedCardID: String?
    @State private var inspectedDate: Date?
    @State private var timelineScroll = Date()
    @State private var windowMonths = 1
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
            let horizon = outlook.sampleDates.last ?? model.now.addingTimeInterval(1)
            let visibleDuration = RetentionTimeline.duration(months: windowMonths, now: model.now, start: outlook.startDate, end: horizon)
            let latestStart = max(outlook.startDate, horizon.addingTimeInterval(-visibleDuration))
            let windowStart = min(max(timelineScroll, outlook.startDate), latestStart)
            let window = DateInterval(start: windowStart, end: min(horizon, windowStart.addingTimeInterval(visibleDuration)))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Memory outlook").font(theme.font(.section))
                    Spacer()
                    Button { openTarget() } label: {
                        Text("Target \(Int((outlook.target * 100).rounded()))%")
                        Image(systemName: "chevron.right").font(.caption)
                    }.font(.subheadline).frame(minHeight: 44)
                }
                HStack(spacing: 12) {
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
                    Spacer(minLength: 4)
                    Menu {
                        Button("1 month") { setWindow(1) }
                        Button("2 months") { setWindow(2) }
                        Button("3 months") { setWindow(3) }
                        Button("Full horizon") { setWindow(0) }
                        if windowMonths > 0 { Button("Back to today") { timelineScroll = min(model.now, latestStart); inspectedDate = nil } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(windowMonths == 0 ? "Full horizon" : windowMonths == 1 ? "1 month" : "\(windowMonths) months")
                            Image(systemName: "chevron.down").font(.caption2)
                        }.font(.caption).frame(minHeight: 44)
                    }.accessibilityIdentifier("deck-graph-range")
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
                    let endpoint = DeckMemoryOutlook.recallAt(window.end, dates: outlook.sampleDates, probabilities: values)
                    let axis = DeckMemoryOutlook.recallAxisDomain(endpoint: endpoint)
                    HStack(spacing: 4) {
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
                                .foregroundStyle(palette.answerSelectionInk)
                                .lineStyle(StrokeStyle(lineWidth: 1.3, dash: [2, 4]))
                                .interpolationMethod(.monotone)
                        }
                        ForEach(DeckMemoryOutlook.verticalReviewPoints(selected?.projection ?? outlook.projection, reviewDates: selected?.reviewDates ?? outlook.reviewDates).enumerated().map { Point(id: $0.offset, date: $0.element.date, probability: $0.element.probability) }) { point in
                            LineMark(x: .value("Date", point.date), y: .value("Recall", point.probability * 100), series: .value("Period", "Planned reviews"))
                                .foregroundStyle(curveColor).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .interpolationMethod(.linear)
                        }
                        if let inspectedDate, let date = (selected?.reviewDates ?? outlook.reviewDates).min(by: { abs($0.timeIntervalSince(inspectedDate)) < abs($1.timeIntervalSince(inspectedDate)) }) {
                            RuleMark(x: .value("Selected review", date))
                                .foregroundStyle(palette.accentInk)
                                .annotation(position: .top) { Text(date, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(palette.primaryText) }
                        }
                        PointMark(x:.value("Today",model.now),y:.value("Recall today",(values.first ?? 0) * 100))
                            .foregroundStyle(curveColor).symbolSize(64)
                    }
                    .chartYScale(domain: axis)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: axis.lowerBound)
                    .chartPlotStyle { plot in plot.clipped() }
                    .chartXScale(domain: outlook.startDate...horizon)
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDuration)
                    .chartScrollPosition(x: $timelineScroll)
                    .chartXSelection(value: $inspectedDate)
                    .onChange(of: windowMonths) { _, _ in timelineScroll = min(model.now, latestStart); inspectedDate = nil }
                    .onChange(of: selectedCardID) { _, _ in timelineScroll = min(model.now, latestStart); inspectedDate = nil }
                    .onAppear { timelineScroll = min(model.now, latestStart) }
                    .chartXAxis(.hidden)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [axis.lowerBound, (axis.lowerBound + 100) / 2, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let percent = value.as(Double.self) { Text(percent, format: .number.precision(.fractionLength(0))) }
                            }
                        }
                    }
                    .frame(height: chartHeight)
                    .accessibilityIdentifier("deck-retention-chart")
                    .accessibilityAction(named: "Next window") { timelineScroll = min(latestStart, timelineScroll.addingTimeInterval(visibleDuration)) }
                    .accessibilityAction(named: "Previous window") { timelineScroll = max(outlook.startDate, timelineScroll.addingTimeInterval(-visibleDuration)) }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selectedCardID)
                    .accessibilityLabel("Estimated recall \(Int((values.first ?? 0) * 100)) percent today, against a \(Int(outlook.target * 100)) percent target; visible scale \(Int(axis.lowerBound.rounded())) to 100 percent; forecast assumes Good at each planned review")
                    GeometryReader { geometry in
                        let projection = selected?.projection ?? outlook.projection
                        let planned = DeckMemoryOutlook.recallAt(window.end, dates: projection.map(\.date), probabilities: projection.map(\.probability))
                        let labels = edgeLabels(target: outlook.target, planned: planned, noReview: endpoint, axis: axis, height: geometry.size.height)
                        ForEach(labels) { label in
                            Text(label.value, format: .percent.precision(.fractionLength(0)))
                                .font(.caption2).monospacedDigit().foregroundStyle(label.color)
                                .accessibilityLabel(label.name + " " + label.value.formatted(.percent.precision(.fractionLength(0))))
                                .accessibilityIdentifier("deck-curve-label-" + label.name)
                                .position(x: geometry.size.width / 2, y: label.y)
                        }
                    }.frame(width: 46, height: chartHeight).allowsHitTesting(false)
                    }
                    HStack(spacing: 16) {
                        Label("Planned reviews", systemImage: "line.diagonal").foregroundStyle(curveColor)
                        Label("No more reviews", systemImage: "line.diagonal").foregroundStyle(palette.answerSelectionInk)
                    }.font(.caption)
                    HStack { Text(window.start, format: .dateTime.month(.abbreviated).day().year()); Spacer(); Text(window.end, format: .dateTime.month(.abbreviated).day().year()) }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("deck-graph-window")
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
                if !(selected?.reviewDates ?? outlook.reviewDates).filter({ window.contains($0) }).isEmpty {
                    Text("Planned · " + (selected?.reviewDates ?? outlook.reviewDates).filter { window.contains($0) }.prefix(3).map { $0.formatted(.dateTime.month(.abbreviated).day()) }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                if model.library.isDeckSuspended(deck.id) {
                    Text("This notebook is suspended. Its forecast includes no future reviews until you resume it.")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                Text("Dates use real calendar spacing. Dotted forecast assumes Good at due dates. New and unsupported cards are excluded.")
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

    private struct EdgeLabel: Identifiable {
        var id: String { name }
        let name: String
        let value: Double
        let color: Color
        var y: CGFloat
    }
    private func edgeLabels(target: Double, planned: Double?, noReview: Double?, axis: ClosedRange<Double>, height: CGFloat) -> [EdgeLabel] {
        var labels = [("Target", Optional(target), palette.accentInk), ("Planned reviews", planned, curveColor), ("No more reviews", noReview, palette.answerSelectionInk)].compactMap { name, value, color -> EdgeLabel? in
            guard let value else { return nil }
            let y = height * CGFloat((100 - value * 100) / (100 - axis.lowerBound))
            return EdgeLabel(name: name, value: value, color: color, y: min(max(8, y), height - 8))
        }.sorted { $0.y < $1.y }
        for index in labels.indices.dropFirst() { labels[index].y = max(labels[index].y, labels[index - 1].y + 17) }
        if let last = labels.last, last.y > height - 8 {
            labels[labels.count - 1].y = height - 8
            for index in labels.indices.dropLast().reversed() { labels[index].y = min(labels[index].y, labels[index + 1].y - 17) }
        }
        return labels
    }

    private func setWindow(_ months: Int) {
        windowMonths = months; inspectedDate = nil
    }

    private var useDeadline: Bool { (deck.examDate ?? .distantPast) > model.now }

    private func openTarget() {
        useCustomTarget = deck.desiredRetention != nil
        target = deck.desiredRetention ?? model.library.settings.desiredRetention
        editingTarget = true
    }
}
