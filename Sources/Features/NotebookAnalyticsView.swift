import SwiftUI
import Charts
import LearningCore
import StudyApplication
import DesignSystem

struct NotebookAnalyticsView: View {
    @Bindable var model: EngramModel
    let deckID: String
    @State private var analytics: NotebookAnalytics?
    @State private var error: String?
    @State private var range = 28
    var body: some View {
        Form {
            EngramListSection("Study goals") {
                NavigationLink("Deadline learning · plan & data") { DeadlineLearningView(model: model, deckID: deckID) }
            }
            if let analytics {
                if analytics.isDemo {
                    EngramListSection {
                        Label("Sample learning data", systemImage: "sparkles").font(.headline)
                        Text("28 days of synthetic answers. Every model runs with illustrative parameters. These charts are not your results and do not change your learning settings.").font(.subheadline).engramSecondaryText()
                    }
                }
                EngramListSection("Study activity") {
                    Picker("History", selection: $range) {
                        Text("7 days").tag(7); Text("28 days").tag(28); Text("All").tag(0)
                    }.pickerStyle(.segmented)
                    metric("Accepted attempts", value: "\(analytics.observed.acceptedAttempts)", subtitle: "Accepted attempts across this notebook's recorded history")
                    AnalyticsTimeChart(points: daily(analytics.evidence.filter { $0.acceptance == .accepted }, value: { _ in 1 }), kind: .bars, unit: "Attempts")
                    metric("Study time", value: analytics.observed.measuredStudySeconds.map { "\(Int($0 / 60)) min" } ?? "No measured time", subtitle: "Measured active time · \(analytics.observed.timedAttempts) timed attempts")
                    AnalyticsTimeChart(points: daily(analytics.evidence.filter { $0.acceptance == .accepted && $0.studySeconds != nil }, value: { ($0.studySeconds ?? 0) / 60 }), kind: .bars, unit: "Minutes")
                }
                EngramListSection("Observed results") {
                    outcome("Delayed recall", outcome: analytics.observed.delayedRecall, evidence: analytics.evidence.filter { $0.kind == .recall && ($0.delaySeconds ?? 0) >= 86400 })
                    outcome("Unfamiliar questions", outcome: analytics.observed.unfamiliarQuestions, evidence: analytics.evidence.filter { $0.kind != .recall && $0.unfamiliar == true })
                    metric("Confirmed errors by skill", value: "", subtitle: "Skills attached to confirmed incorrect answers")
                    AnalyticsBarChart(values: analytics.observed.skillErrors.keys.sorted().map { .init(label: $0, value: Double(analytics.observed.skillErrors[$0] ?? 0)) }, unit: "Errors")
                }
                EngramListSection("FSRS · Memory") {
                    metric("Recall forecast", value: analytics.predictedRecall.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "No estimate", subtitle: "\(analytics.recallEstimatedCards) of \(analytics.recallTotalCards) cards estimated")
                    AnalyticsTimeChart(points: analytics.recallForecast, kind: .line, unit: "Recall", percent: true)
                    Text("Estimated recall over the next 14 days if you do no further reviews. This is a memory prediction, separate from observed accuracy and skill mastery.").font(.caption).engramSecondaryText()
                    let cards = model.library.liveCards.filter { $0.deckID == deckID && !$0.suspended }
                    if !analytics.isDemo {
                        metric("Review readiness", value: "\(cards.count) cards", subtitle: "Current scheduling status")
                        AnalyticsBarChart(values: [.init(label: "Ready now", value: Double(cards.filter { $0.schedule.due <= model.now }.count)), .init(label: "Due later", value: Double(cards.filter { $0.schedule.due > model.now }.count))], unit: "Cards")
                    }
                }
                ForEach(analytics.components, id: \.description.model.rawValue) { component in
                    componentSection(component, demo: analytics.isDemo)
                }
                EngramListSection {
                    Text("Observed results and model estimates answer different questions. These graphs do not show which model causes better learning.").font(.caption).engramSecondaryText()
                    if !analytics.isDemo { NavigationLink("Learning & practice settings") { UnderstandingSettingsView(model: model, deckID: deckID) } }
                }
            } else if let error { EngramListSection { Text(error).font(.subheadline) } }
            else { ProgressView("Loading analytics") }
        }.modifier(UtilityListStyle()).navigationTitle("Analytics")
            .task(id: model.library.revision) { await load() }
            .refreshable { await load() }
    }
    private func metric(_ title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline); Spacer()
                if !value.isEmpty { Text(value).font(.title3.weight(.semibold)).monospacedDigit() }
            }
            Text(subtitle).font(.caption).engramSecondaryText()
        }.padding(.top, 8)
    }
    private func daily(_ evidence: [LearnerEvidence], value: (LearnerEvidence) -> Double) -> [NotebookAnalytics.Point] {
        let calendar = Calendar.current
        let end = model.now
        let start = calendar.date(byAdding: .day, value: -max(0, range - 1), to: calendar.startOfDay(for: end))!
        let filtered = evidence.filter { range == 0 || $0.occurredAt >= start }
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.occurredAt) }
        // Only recorded days: missing days are not measured zero-duration sessions.
        return grouped.keys.sorted().map { .init(date: $0, series: "Recorded", value: grouped[$0]!.reduce(0) { $0 + value($1) }) }
    }
    @ViewBuilder private func outcome(_ title: String, outcome: LearnerDashboard.Outcome, evidence: [LearnerEvidence]) -> some View {
        metric(title, value: outcome.attempts == 0 ? "No results" : (Double(outcome.correct) / Double(outcome.attempts)).formatted(.percent.precision(.fractionLength(0))), subtitle: outcome.label + " · unassisted answers only")
        let eligible = evidence.filter { $0.acceptance == .accepted && $0.assisted == false && $0.correct != nil }
        let correct = daily(eligible.filter { $0.correct == true }, value: { _ in 1 }).map { NotebookAnalytics.Point(date: $0.date, series: "Correct", value: $0.value) }
        let incorrect = daily(eligible.filter { $0.correct == false }, value: { _ in 1 }).map { NotebookAnalytics.Point(date: $0.date, series: "Incorrect", value: $0.value) }
        AnalyticsTimeChart(points: correct + incorrect, kind: .bars, unit: "Answers")
    }
    @ViewBuilder private func componentSection(_ component: NotebookAnalytics.Component, demo: Bool) -> some View {
        EngramListSection(title(component.description.model)) {
            Text(component.description.purpose).font(.subheadline)
            Text(demo ? "Illustrative model · synthetic parameters" : "\(component.mode.rawValue.capitalized) · \(component.description.readiness)").font(.caption).engramSecondaryText()
            let predicted = component.questions.filter { $0.prediction != nil }
            if predicted.isEmpty {
                AnalyticsEmptyChart(message: component.mode == .off ? "Model is off. Enable a calibrated model in Learning & practice settings to see estimates." : "No compatible estimates yet. A reviewed model and matching learning history are needed.")
            } else {
                if component.description.model == .dynamicRasch {
                    metric("Ability over time", value: "", subtitle: "Rasch scale · shaded band is the conditional 95% interval")
                    AnalyticsTimeChart(points: component.abilityHistory, kind: .ability, unit: "Ability")
                    metric("Question difficulty", value: "", subtitle: "Higher values mean harder questions on this model's scale")
                    AnalyticsBarChart(values: predicted.compactMap { q in q.calibratedDifficulty.map { .init(label: short(q.prompt), value: $0) } }, unit: "Difficulty")
                }
                if component.description.model == .bkt || component.description.model == .dina {
                    let skills = skillValues(predicted)
                    metric(component.description.model == .dina ? "Assessment skill profile" : "Skill mastery estimates", value: "", subtitle: component.description.model == .dina ? "Current supported assessment only" : "Conditional BKT estimates")
                    AnalyticsBarChart(values: skills, unit: "Estimated mastery", percent: true)
                }
                metric("Predicted correct by question", value: "", subtitle: component.description.model == .das3h ? "Performance estimate from spaced practice; not a mastery score" : "Estimated chance of a correct answer")
                AnalyticsBarChart(values: predicted.compactMap { q in q.prediction?.probabilityCorrect.map { .init(label: short(q.prompt), value: $0) } }, unit: "Predicted correct", percent: true)
                DisclosureGroup("Questions & model details") {
                    ForEach(predicted) { question in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(question.prompt).font(.subheadline)
                            if let p = question.prediction {
                                if let value = p.probabilityCorrect { Text(value, format: .percent.precision(.fractionLength(1))).font(.caption) }
                                Text("Skills: " + question.mapping.skillIDs.joined(separator: ", ")).font(.caption).engramSecondaryText()
                                Text("Artifact \(p.artifactRevision) · evidence revision \(p.evidenceRevision)").font(.caption2).engramSecondaryText()
                            }
                        }
                    }
                    Text(component.description.limitations).font(.caption).engramSecondaryText()
                }
            }
        }
    }
    private func short(_ text: String) -> String { text.count > 38 ? String(text.prefix(35)) + "…" : text }
    private func skillValues(_ questions: [NotebookAnalytics.Question]) -> [AnalyticsBarChart.Value] {
        var values: [String: [Double]] = [:]
        for q in questions { for (skill, value) in q.prediction?.skillProbabilities ?? [:] { values[skill, default: []].append(value) } }
        return values.keys.sorted().map { .init(label: $0, value: values[$0]!.reduce(0, +) / Double(values[$0]!.count)) }
    }
    private func title(_ id: LearnerModelID) -> String {
        switch id { case .das3h: return "DAS3H · Skill performance"; case .bkt: return "BKT · Skill mastery"; case .dynamicRasch: return "Dynamic IRT · Ability & difficulty"; case .dina: return "DINA · Skill diagnosis" }
    }
    private func load() async {
        let account = model.understanding.account(model), library = model.activeLibraryID
        analytics = nil; error = nil
        await model.understanding.configure(model)
        do {
            let result = try await model.service.notebookAnalytics(deckID: deckID, now: model.now)
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            analytics = result
        } catch {
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            self.error = "Analytics unavailable. Try refreshing after the current attempt finishes."
        }
    }
}

struct AnalyticsEmptyChart: View {
    var message = "No recorded data yet. Complete some attempts to see this graph."
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line").font(.title).engramSecondaryText()
            Text(message).font(.subheadline).multilineTextAlignment(.center).engramSecondaryText()
        }.frame(maxWidth: .infinity, minHeight: 150).padding(12)
    }
}

struct AnalyticsTimeChart: View {
    enum Kind { case bars, line, ability }
    let points: [NotebookAnalytics.Point]
    let kind: Kind
    let unit: String
    var percent = false
    var target: Double? = nil
    var emptyMessage = "No recorded data yet. Complete some attempts to see this graph."
    @State private var selected: Date?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { theme.palette(for: scheme).accentInk }
    var body: some View {
        if points.isEmpty { AnalyticsEmptyChart(message: emptyMessage) }
        else {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(points) { p in
                        if kind == .bars {
                            BarMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                                .foregroundStyle(by: .value("Result", p.series))
                        } else {
                            if let lower = p.lower, let upper = p.upper {
                                AreaMark(x: .value("Date", p.date), yStart: .value("Lower", lower), yEnd: .value("Upper", upper)).foregroundStyle(ink.opacity(0.13))
                            }
                            LineMark(x: .value("Date", p.date), y: .value(unit, p.value * (percent ? 100 : 1)), series: .value("Estimate", p.series)).foregroundStyle(by: .value("Result", p.series))
                            PointMark(x: .value("Date", p.date), y: .value(unit, p.value * (percent ? 100 : 1))).foregroundStyle(by: .value("Result", p.series)).symbolSize(18)
                        }
                    }
                    if let target {
                        RuleMark(y: .value("Target", target * (percent ? 100 : 1))).foregroundStyle(.secondary).lineStyle(.init(dash: [4, 4]))
                    }
                    if let selected {
                        RuleMark(x: .value("Selected", selected)).foregroundStyle(.secondary).lineStyle(.init(dash: [3, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: seriesNames, range: seriesNames.map { ($0 == "Incorrect" || $0 == "Without practice") ? theme.palette(for: scheme).secondaryText.opacity(0.55) : ink })
                .chartLegend(seriesNames.count > 1 ? .visible : .hidden)
                .chartYScale(domain: percent ? 0...100 : automaticDomain)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let number = v.as(Double.self) { Text(number.formatted(.number.precision(.fractionLength(kind == .ability ? 1 : 0))) + (percent ? "%" : "")) } } } }
                .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 18))
                .chartXSelection(value: $selected)
                .frame(height: 190)
                if let selected, let closest = points.min(by: { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }) {
                    Text("\(closest.date.formatted(date: .abbreviated, time: .omitted)) · \(closest.series): \(percent ? closest.value.formatted(.percent.precision(.fractionLength(1))) : closest.value.formatted(.number.precision(.fractionLength(1)))) \(percent ? "" : unit.lowercased())").font(.caption).monospacedDigit()
                } else { Text("Touch and hold to inspect a date").font(.caption2).engramSecondaryText() }
            }.padding(.vertical, 8)
        }
    }
    private var seriesNames: [String] { Array(Set(points.map(\.series))).sorted() }
    private var automaticDomain: ClosedRange<Double> {
        let grouped = Dictionary(grouping: points, by: \.date)
        let high = kind == .bars ? grouped.values.map { $0.reduce(0) { $0 + $1.value } }.max() ?? 1 : points.map { $0.upper ?? $0.value }.max() ?? 1
        let low = kind == .ability ? min(0, points.map { $0.lower ?? $0.value }.min() ?? 0) : 0
        return low...max(low + 1, high * 1.1)
    }
}

struct AnalyticsBarChart: View {
    struct Value: Identifiable { var id: String { label }; let label: String; let value: Double }
    let values: [Value]
    let unit: String
    var percent = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if values.isEmpty { AnalyticsEmptyChart() }
        else {
            Chart(values) { item in
                BarMark(x: .value(unit, item.value * (percent ? 100 : 1)), y: .value("Question or skill", item.label))
                    .foregroundStyle(theme.palette(for: scheme).accentInk)
                    .annotation(position: .trailing) { Text(percent ? item.value.formatted(.percent.precision(.fractionLength(0))) : item.value.formatted(.number.precision(.fractionLength(1)))).font(.caption2).monospacedDigit() }
            }
            .chartXScale(domain: percent ? 0...110 : min(0, (values.map(\.value).min() ?? 0) * 1.2)...max(1, (values.map(\.value).max() ?? 1) * 1.25))
            .chartXScale(range: .plotDimension(startPadding: 4, endPadding: 20))
            .chartYAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { v in AxisGridLine(); AxisValueLabel { if let n = v.as(Double.self), !percent || n <= 100 { Text(n.formatted(.number.precision(.fractionLength(0))) + (percent ? "%" : "")) } } } }
            .frame(height: max(120, CGFloat(values.count) * 46)).padding(.vertical, 8)
        }
    }
}
