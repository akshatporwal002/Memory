import SwiftUI
import DesignSystem
import Charts
import LearningCore
import StudyApplication

struct ActivityView: View {
    let model: EngramModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    @State private var period: ActivityPeriod = .week
    @State private var offset = 0
    @State private var selectedDate: Date?
    @State private var summary: ActivitySummary?
    @State private var report: ActivityReviewReport?
    @State private var previous: ActivityReviewReport?
    @State private var refreshedAt = Date()
    private var window: ActivityWindow { ActivityWindow(period: period, offset: offset, now: refreshedAt, settings: model.library.settings, earliestReview: model.library.activeReviews.map(\.reviewedAt).min()) }
    private var selected: DateInterval? { selectedDate.flatMap { date in window.buckets.first { date >= $0.start && date < $0.end } } }
    private var refreshID: String { "\(model.library.revision)-\(period)-\(offset)-\(selectedDate?.timeIntervalSince1970 ?? 0)-\(scenePhase)" }

    var body: some View {
        List {
            EngramListSection {
                HStack {
                    Button { offset -= 1; selectedDate = nil } label: { Image(systemName: "chevron.left").frame(minWidth: EngramShape.touchTarget, minHeight: EngramShape.touchTarget) }.accessibilityLabel("Previous period").disabled(period == .all)
                    Spacer()
                    Text(rangeLabel(selected ?? window.interval)).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    Spacer()
                    Button { offset += 1; selectedDate = nil } label: { Image(systemName: "chevron.right").frame(minWidth: EngramShape.touchTarget, minHeight: EngramShape.touchTarget) }.accessibilityLabel("Next period").disabled(offset >= 0 || period == .all)
                }.buttonStyle(.borderless).listRowSeparator(.hidden)
                if let report, let summary {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.attemptCount, format: .number).font(theme.font(.hero)).monospacedDigit()
                        Text("Review attempts").engramSecondaryText()
                        if selected == nil, let previous, previous.attempts > 0 {
                            let delta = report.attempts - previous.attempts
                            Text("\(abs(delta)) \(delta >= 0 ? "more" : "fewer") than the previous period").font(.caption).engramSecondaryText()
                        }
                    }.padding(.vertical, 4).listRowSeparator(.hidden)
                    Chart(report.points) { point in
                          RectangleMark(xStart: .value("Start", point.interval.start.addingTimeInterval(point.interval.duration * 0.12)),
                                xEnd: .value("End", point.interval.end.addingTimeInterval(-point.interval.duration * 0.12)),
                                yStart: .value("Baseline", 0), yEnd: .value("Review attempts", point.attempts)).cornerRadius(3)
                            .foregroundStyle(selected == nil || selected?.start == point.interval.start ? palette.accentInk : palette.secondaryText)
                            .accessibilityLabel(point.interval.start.formatted(date: .abbreviated, time: period == .today ? .shortened : .omitted))
                            .accessibilityValue("\(point.attempts) attempts, \(point.cards) cards")
                        if selected?.start == point.interval.start {
                            RuleMark(x: .value("Selection", point.interval.start.addingTimeInterval(point.interval.duration / 2)))
                                .foregroundStyle(palette.secondaryText).lineStyle(StrokeStyle(dash: [3]))
                        }
                    }.chartXScale(domain: window.interval.start...window.interval.end)
                        .chartXSelection(value: $selectedDate)
                        .chartGesture { proxy in
                            SpatialTapGesture().onEnded { event in proxy.selectXValue(at: event.location.x) }
                        }
                        .chartYScale(domain: 0...max(1, report.points.map(\.attempts).max() ?? 1))
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .stride(by: Double(max(1, (report.points.map(\.attempts).max() ?? 1) / 4)))) {
                                AxisGridLine().foregroundStyle(palette.hairline)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .chartXAxis {
                            AxisMarks {
                                AxisGridLine().foregroundStyle(palette.hairline)
                                AxisValueLabel().foregroundStyle(palette.secondaryText)
                            }
                        }
                        .environment(\.timeZone, TimeZone(identifier: model.library.settings.timeZoneID) ?? .gmt)
                        .frame(height: typeSize.isAccessibilitySize ? 280 : 180).padding(.vertical, 8).listRowSeparator(.hidden)
                        .accessibilityIdentifier("review-activity-chart")
                    if selectedDate != nil { Button("Show entire period") { selectedDate = nil } }
                    LabeledContent("Cards reviewed", value: summary.reviewedCount.formatted())
                    if summary.attemptCount == 0 { Text("No reviews in this period. Study a deck to see your activity here.").engramSecondaryText() }
                } else { ProgressView("Loading activity…") }
                Group {
                    if typeSize.isAccessibilitySize { periodPicker.pickerStyle(.menu) }
                    else { periodPicker.pickerStyle(.segmented) }
                }.listRowSeparator(.hidden)
            } footer: { Text("Tap the chart to inspect a time. Review totals exclude undone and imported records.") }

            if let summary, let report {
                if report.attempts > 0 {
                    EngramListSection {
                        LabeledContent("Manual ratings", value: report.manual.formatted())
                        LabeledContent("Automatically marked", value: report.automatic.formatted())
                        LabeledContent("Good or Easy", value: "\(report.recalled) of \(report.attempts)")
                    } header: { Text("Review results · entire period") } footer: { Text("Good or Easy is the recorded scheduling grade, not an exam score. Question history shows how each answer was marked.") }
                }
                EngramListSection {
                    LabeledContent("Due now", value: summary.dueCount.formatted())
                    LabeledContent("Retention target", value: model.library.settings.desiredRetention.formatted(.percent.precision(.fractionLength(0))))
                    let counts = summary.decks.reduce(into: [MemoryBucket: Int]()) { totals, deck in for (bucket, count) in deck.counts { totals[bucket, default: 0] += count } }
                    ForEach(MemoryBucket.allCases.filter { counts[$0, default: 0] > 0 }) { bucket in
                        LabeledContent { Text(counts[bucket, default: 0], format: .number).foregroundStyle(bucketColor(bucket, palette: palette)) } label: { Text(bucket.rawValue) }
                    }
                } header: { Text("Memory now") } footer: { Text("Recall is estimated by FSRS from your current schedule. These counts reflect now, regardless of the selected dates.") }
                EngramListSection("Deck activity") {
                    ForEach(summary.decks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { deck in
                        NavigationLink { ActivityDeckPage(model: model, deck: deck, interval: selected ?? window.interval) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(deck.title); Spacer(); Text(deck.questions.reduce(0) { $0 + $1.attempts.count }, format: .number).engramSecondaryText().monospacedDigit() }
                                if !deck.folder.isEmpty { Text(deck.folder).font(.caption).engramSecondaryText() }
                                Text("\(deck.questions.filter { !$0.attempts.isEmpty }.count) reviewed · \(deck.dueCount) due now").font(.caption).engramSecondaryText()
                            }.padding(.vertical, 4)
                        }
                    }
                    if summary.decks.isEmpty { ContentUnavailableView("No activity yet", systemImage: "chart.bar", description: Text("Create a deck to start studying.")) }
                }
                EngramListSection { Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))").font(.caption).engramSecondaryText().frame(maxWidth: .infinity) }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Activity")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .onChange(of: period) { _, _ in offset = 0; selectedDate = nil }
            .task(id: refreshID) {
                guard scenePhase == .active else { return }
                repeat {
                    let now = Date()
                    let range = ActivityWindow(period: period, offset: offset, now: now, settings: model.library.settings, earliestReview: model.library.activeReviews.map(\.reviewedAt).min())
                    let picked = selectedDate.flatMap { date in range.buckets.first { date >= $0.start && date < $0.end } }
                    let result = await model.service.activity(in: model.library, period: period, now: now, interval: picked ?? range.interval)
                    guard !Task.isCancelled else { return }
                    summary = result; report = ActivityReviewReport.make(in: model.library, window: range, now: now)
                    previous = period == .all ? nil : ActivityReviewReport.make(in: model.library, window: ActivityWindow(period: period, offset: offset - 1, now: now, settings: model.library.settings), now: now)
                    refreshedAt = now
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                } while !Task.isCancelled
            }
    }
    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            Text("Day").tag(ActivityPeriod.today); Text("Week").tag(ActivityPeriod.week)
            Text("Month").tag(ActivityPeriod.month); Text("All").tag(ActivityPeriod.all)
        }
    }
    private func rangeLabel(_ range: DateInterval) -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: model.library.settings.timeZoneID); formatter.dateStyle = .medium
        if period == .today { formatter.timeStyle = selected == nil ? .none : .short; return formatter.string(from: range.start) }
        if selected != nil && range.duration <= 25 * 3600 { return formatter.string(from: range.start) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = formatter.timeZone
        let lastDay = calendar.date(byAdding: .day, value: -1, to: range.end) ?? range.end
        return formatter.string(from: range.start) + " – " + formatter.string(from: lastDay)
    }
}

private func bucketColor(_ bucket: MemoryBucket, palette: EngramPalette) -> Color {
    switch bucket { case .atTarget: palette.primaryText; case .belowTarget: palette.againInk; case .learning: palette.accentInk; case .unstudied, .unavailable: palette.secondaryText }
}

private struct ActivityDeckPage: View {
    let model: EngramModel
    let deck: ActivityDeck
    let interval: DateInterval
    @State private var filter: ActivityCardFilter = .all
    @State private var search = ""
    @State private var limit = 50
    var body: some View {
        List {
            EngramListSection("Current memory") {
                ForEach(MemoryBucket.allCases.filter { deck.counts[$0, default: 0] > 0 }) { bucket in
                    LabeledContent(bucket.rawValue, value: deck.counts[bucket, default: 0].formatted())
                }
                if deck.suspendedCount > 0 { Text("\(deck.suspendedCount) suspended cards excluded").engramSecondaryText() }
            }
            EngramListSection {
                Picker("Questions", selection: $filter) { ForEach(ActivityCardFilter.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                let questions = deck.questions.filter { $0.matches(filter) && (search.isEmpty || $0.prompt.localizedCaseInsensitiveContains(search)) }
                ForEach(questions.prefix(limit)) { question in
                    NavigationLink { ActivityQuestionPage(model: model, question: question) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.prompt).lineLimit(3)
                            Text("\(question.attempts.count) attempts · \(question.outcome)").font(.caption).engramSecondaryText()
                        }.padding(.vertical, 4)
                    }
                }
                if questions.count > limit { Button("Show more questions") { limit += 50 } }
                if questions.isEmpty { Text("No questions match this filter.").engramSecondaryText() }
            } header: { Text("Questions") } footer: { Text("Review history is limited to the selected activity period. Memory and due status reflect now.") }
        }.modifier(UtilityListStyle()).navigationTitle(deck.title).engramInlineTitle().searchable(text: $search, prompt: "Search questions")
            .onChange(of: filter) { _, _ in limit = 50 }
    }
}

private struct ActivityQuestionPage: View {
    let model: EngramModel
    let question: ActivityQuestion
    var body: some View {
        List {
            EngramListSection("Question") { Text(question.prompt).textSelection(.enabled) }
            EngramListSection("Answer") { CardContentView(text: question.answer, media: model.library.media) }
            EngramListSection("Current schedule") {
                LabeledContent("Memory", value: question.bucket.rawValue)
                if question.bucket != .unstudied { LabeledContent("Next due", value: question.due.formatted(date: .abbreviated, time: .shortened)) }
            }
            EngramListSection("Review history · selected period") {
                ForEach(question.attempts) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(event.rating.label).font(.headline); Spacer(); Text(event.assessment == nil ? "Manual" : "Automatic").font(.caption).engramSecondaryText() }
                        Text(event.reviewedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).engramSecondaryText()
                        if let assessment = event.assessment {
                            Text(assessment.outcome.rawValue.capitalized).font(.subheadline)
                            Text(assessment.reason).font(.subheadline).engramSecondaryText()
                        }
                    }.padding(.vertical, 4).accessibilityElement(children: .combine)
                }
                if question.attempts.isEmpty { Text("No reviews in this period.").engramSecondaryText() }
            }
        }.modifier(UtilityListStyle()).navigationTitle("Question History").engramInlineTitle()
    }
}
