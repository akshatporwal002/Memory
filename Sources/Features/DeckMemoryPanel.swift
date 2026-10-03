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
    @State private var inspectedDate: Date?
    @State private var windowAnchor: Date?
    @State private var windowMonths = 2
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
            let window = MemoryGraphWindow.interval(anchor: windowAnchor ?? model.now, months: windowMonths, start: outlook.startDate, end: outlook.sampleDates.last ?? model.now.addingTimeInterval(1))
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
                    let axis = DeckMemoryOutlook.recallAxisDomain(plateau: values.last)
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
                        ForEach(selected?.projection ?? outlook.projection) { point in
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
                    .chartPlotStyle { plot in plot.clipped() }
                    .chartXScale(domain: window.start...window.end)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle().fill(.clear).contentShape(Rectangle())
                                .gesture(DragGesture(minimumDistance: 24).onEnded { drag in
                                    guard windowMonths > 0, abs(drag.translation.width) > abs(drag.translation.height) * 1.5 else { return }
                                    moveWindow(drag.translation.width < 0 ? 1 : -1, window: window)
                                })
                                .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                                    guard let frame = proxy.plotFrame else { return }
                                    inspectedDate = proxy.value(atX: tap.location.x - geometry[frame].origin.x, as: Date.self)
                                })
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading, values: [axis.lowerBound, ((axis.lowerBound + 100) / 2).rounded(), 100]) }
                    .frame(height: 180)
                    .accessibilityIdentifier("deck-retention-chart")
                    .accessibilityAction(named: "Next window") { moveWindow(1, window: window) }
                    .accessibilityAction(named: "Previous window") { moveWindow(-1, window: window) }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: selectedCardID)
                    .accessibilityLabel("Estimated recall \(Int((values.first ?? 0) * 100)) percent today, against a \(Int(outlook.target * 100)) percent target; forecast assumes Good at each planned review")
                    HStack(spacing: 16) {
                        Label("Planned reviews", systemImage: "line.diagonal").foregroundStyle(curveColor)
                        Label("No more reviews", systemImage: "line.diagonal").foregroundStyle(palette.answerSelectionInk)
                    }.font(.caption)
                    HStack { Text(window.start, format: .dateTime.month(.abbreviated).day().year()); Spacer(); Text(window.end, format: .dateTime.month(.abbreviated).day().year()) }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("deck-graph-window")
                        .font(.caption).foregroundStyle(palette.secondaryText).padding(.leading, 28)
                    Menu {
                        Button("1 month") { setWindow(1) }
                        Button("2 months") { setWindow(2) }
                        Button("3 months") { setWindow(3) }
                        Button("Full horizon") { setWindow(0) }
                        if windowMonths > 0 { Button("Back to today") { windowAnchor = nil; inspectedDate = nil } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(windowMonths == 0 ? "Full horizon" : "\(windowMonths) months")
                            Image(systemName: "chevron.down").font(.caption2)
                        }.font(.caption).frame(minHeight: 44)
                    }.accessibilityIdentifier("deck-graph-range")
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
                Text("Solid line: review history. Dotted forecast assumes Good at due dates; actual answers and daily limits can change it. Scale starts 10 points below the no-more-reviews curve’s endpoint. New and unsupported cards are excluded.")
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

    private func setWindow(_ months: Int) {
        windowMonths = months; windowAnchor = nil; inspectedDate = nil
    }
    private func moveWindow(_ direction: Int, window: DateInterval) {
        guard windowMonths > 0 else { return }
        windowAnchor = Calendar.current.date(byAdding: .month, value: direction * windowMonths, to: window.start)
        inspectedDate = nil
    }

    private var useDeadline: Bool { (deck.examDate ?? .distantPast) > model.now }

    private func openTarget() {
        useCustomTarget = deck.desiredRetention != nil
        target = deck.desiredRetention ?? model.library.settings.desiredRetention
        editingTarget = true
    }
}
