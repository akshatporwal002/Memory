import SwiftUI
import Charts
import LearningCore
import StudyApplication
import DesignSystem

/// Notebook-local research surface using the same rows and typography as Analytics.
struct DeadlineLearningView: View {
    @Bindable var model: EngramModel
    let deckID: String
    @State private var record: DeadlineRecord?
    @State private var plan: DeadlinePlan?
    @State private var deadline = Date().addingTimeInterval(30 * 86400)
    @State private var target = 80.0
    @State private var minutes = 15
    @State private var loaded = false
    @State private var working = false
    @State private var error: String?
    @State private var recording = false
    @State private var confirmReset = false
    @State private var sample = false
    @Environment(\.engramTheme) private var theme
    var body: some View {
        Form {
            if sample {
                EngramListSection {
                    Label("Sample deadline plan", systemImage: "sparkles").font(.headline)
                    Text("Synthetic answers and provisional planning assumptions. Changing this preview does not save a personal goal or add cards to your review queue.").font(.caption).engramSecondaryText()
                }
            }
            EngramListSection("Deadline learning") {
                Text("Plan your practice around a date and a target.").font(theme.font(.section))
                Text("Experimental · estimates use provisional learning assumptions, not calibrated exam predictions.").font(.caption).engramSecondaryText()
                DatePicker("Learn by", selection: $deadline, in: Date()...Date().addingTimeInterval(366 * 86400), displayedComponents: .date)
                Stepper("Target performance · \(Int(target))%", value: $target, in: 10...99)
                Stepper("Daily study budget · \(minutes) min", value: $minutes, in: 1...120)
                Button(sample ? "Update sample plan" : record == nil ? "Create study plan" : "Save goal & refresh target cards") {
                    if sample { Task { await updateSample() } } else if record == nil { Task { await save() } } else { confirmReset = true }
                }.disabled(working || !loaded)
                if !sample { Text("Saving freezes the current eligible cards as the target set. Updating the goal replaces this set and starts a new forecast history.").font(.caption).engramSecondaryText() }
            }
            if let error { EngramListSection { Text(error).foregroundStyle(.red) } }
            if let record, let plan {
                EngramListSection("Deadline forecast") {
                    AnalyticsBarChart(values: [
                        .init(label: "With this plan", value: plan.forecast),
                        .init(label: "Without practice", value: plan.baseline),
                        .init(label: "Your target", value: record.goal.target)
                    ], unit: "Deadline performance", percent: true)
                    Text("Expected performance at the deadline · all three bars use the same target cards").font(.caption).engramSecondaryText()
                    LabeledContent("Planned study time", value: "\(plan.plannedMinutes) min")
                    LabeledContent("Target cards", value: "\(record.goal.items.count)")
                    if record.goal.deadline <= Date() { Text("Deadline passed. Set a future date to plan again.").font(.caption) }
                    else if plan.staleItems > 0 { Text("\(plan.staleItems) target cards changed or became unavailable. Refresh the target set to plan again.").font(.caption) }
                    else if plan.forecast < record.goal.target { Text("The prototype did not find a plan reaching your target within its budget and search limits.").font(.caption) }
                    Text("This is expected performance on your target cards, not a guaranteed test mark. Review gains, new-card knowledge and half-lives are unvalidated assumptions. Actual outcomes may differ substantially.").font(.caption).engramSecondaryText()
                    if !sample { Button("Recalculate & save forecast") { Task { await recalculate() } }.disabled(working) }
                }
                EngramListSection("Practice plan") {
                    let today = plan.actions.filter { $0.date <= Date() }
                    if sample { Text("Preview only · sample cards stay outside your study queue.").font(.caption).engramSecondaryText() }
                    else if today.isEmpty { Text("No practice planned right now.") }
                    else {
                        Button("Study \(today.count) planned cards") { Task { await start() } }
                            .disabled(working || plan.staleItems > 0 || record.goal.deadline <= Date())
                    }
                    let dates = Array(Set(plan.actions.map(\.date))).sorted()
                    Text("Daily study workload").font(.headline)
                    AnalyticsTimeChart(points: dates.map { date in
                        .init(date: date, series: "Planned minutes", value: plan.actions.filter { $0.date == date }.reduce(0) { $0 + $1.seconds } / 60)
                    }, kind: .bars, unit: "Minutes", emptyMessage: "No practice actions in the current plan. Check the forecast, target and available budget.")
                    Text("Cards per study day").font(.headline)
                    AnalyticsTimeChart(points: dates.map { date in
                        .init(date: date, series: "Planned cards", value: Double(plan.actions.filter { $0.date == date }.count))
                    }, kind: .bars, unit: "Cards", emptyMessage: "No cards scheduled by the current deadline plan.")
                    DisclosureGroup("Daily plan details") {
                    ForEach(Array(dates.prefix(14)), id: \.self) { date in
                        let actions = plan.actions.filter { $0.date == date }
                        LabeledContent(date.formatted(date: .abbreviated, time: .omitted), value: "\(actions.count) cards · \(Int(ceil(actions.reduce(0) { $0 + $1.seconds } / 60))) min")
                    }
                    }
                    if dates.count > 14 { Text("\(dates.count - 14) more study days in the exported plan.").font(.caption) }
                    Text("Recommendations are optional. Recalculate after studying; FSRS schedules are updated normally when you answer a card.").font(.caption).engramSecondaryText()
                }
                EngramListSection("Observations") {
                    Text("\(plan.observations) accepted unaided answers").font(.headline)
                    AnalyticsBarChart(values: plan.observations == 0 ? [] : [
                        .init(label: "Correct", value: Double(plan.observedCorrect)),
                        .init(label: "Incorrect", value: Double(plan.observations - plan.observedCorrect))
                    ], unit: "Answers")
                    LabeledContent("Measured active time", value: "\(Int(plan.timedSeconds / 60)) min")
                    Text("Target question types").font(.headline)
                    AnalyticsBarChart(values: Array(Set(record.goal.items.map(\.questionType))).sorted().map { type in
                        .init(label: type, value: Double(record.goal.items.filter { $0.questionType == type }.count))
                    }, unit: "Cards")
                    Text("Only accepted, unassisted, objectively graded answers matching target question versions inform this model. Manual ratings and missing assistance remain excluded.").font(.caption).engramSecondaryText()
                    if !sample {
                    Toggle("Record learner evidence on this device", isOn: $recording)
                        .onChange(of: recording) { _, value in Task { await setRecording(value) } }
                    }
                    if !sample { Text("This is the existing library-wide local learner-recording preference, separate from research consent and cloud uploads.").font(.caption).engramSecondaryText() }
                }
                EngramListSection("Forecast history") {
                    AnalyticsTimeChart(points: record.forecasts.flatMap { forecast in
                        [NotebookAnalytics.Point(date: forecast.generatedAt, series: "With plan", value: forecast.forecast),
                         NotebookAnalytics.Point(date: forecast.generatedAt, series: "Without practice", value: forecast.baseline)]
                    }, kind: .line, unit: "Deadline performance", percent: true, target: record.goal.target)
                    Text("Dashed line: target · lines track saved predictions for the same deadline, not measured learning progress.").font(.caption).engramSecondaryText()
                    Text("\(record.forecasts.count) \(sample ? "illustrative" : "saved") forecasts · evidence revision \(plan.evidenceRevision)").font(.caption)
                    Text(plan.policyVersion).font(.caption).engramSecondaryText()
                    Text("Forecasts show how predictions changed, not measured mastery. Up to 100 snapshots are kept locally per notebook.").font(.caption).engramSecondaryText()
                    if let data = try? JSONEncoder().encode(plan), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Export current plan & metrics", item: json)
                    }
                    if !sample { Button("Remove deadline goal", role: .destructive) { Task { await remove() } }.disabled(working) }
                }
            }
            if !loaded || working { ProgressView() }
        }
        .modifier(UtilityListStyle()).navigationTitle("Deadline learning")
        .task(id: model.activeLibraryID + ":" + model.understanding.account(model).uuidString) { await load() }
        .refreshable { await load() }
        .confirmationDialog("Replace this goal's target cards and forecast history?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Replace goal") { Task { await save() } }
        }
    }
    private func load() async {
        let account = model.understanding.account(model), library = model.activeLibraryID
        record = nil; plan = nil; loaded = false
        await model.understanding.configure(model)
        do {
            if let preview = try await model.service.deadlineLearningSample(deckID: deckID) {
                guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
                sample = true; record = preview; plan = preview.forecasts.last
                deadline = preview.goal.deadline; target = preview.goal.target * 100; minutes = preview.goal.dailyMinutes
                error = nil; loaded = true; return
            }
            sample = false
            let saved = try await model.service.deadlineRecord(deckID: deckID)
            let forecast = saved == nil ? nil : try await model.service.deadlinePlan(deckID: deckID)
            let status = try await model.service.learnerStatus()
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            record = saved; plan = forecast; recording = status.recordingEnabled
            if let saved { deadline = saved.goal.deadline; target = saved.goal.target * 100; minutes = saved.goal.dailyMinutes }
            error = nil; loaded = true
        } catch { self.error = error.localizedDescription; loaded = true }
    }
    private func updateSample() async {
        working = true; defer { working = false }
        let account = model.understanding.account(model), library = model.activeLibraryID
        do {
            let preview = try await model.service.deadlineLearningSample(deckID: deckID, deadline: deadline, target: target / 100, dailyMinutes: minutes)
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            record = preview; plan = preview?.forecasts.last; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        working = true; defer { working = false }
        do { try await model.service.saveDeadlineGoal(deckID: deckID, deadline: deadline, target: target / 100, dailyMinutes: minutes); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func recalculate() async {
        working = true; defer { working = false }
        do { _ = try await model.service.deadlinePlan(deckID: deckID, saveForecast: true); await load() }
        catch { self.error = error.localizedDescription }
    }
    private func start() async {
        if await model.perform({ _ = try await $0.startDeadlineSession(deckID: deckID, now: Date()) }) { model.reviewPresented = true }
        else { error = model.error }
    }
    private func setRecording(_ value: Bool) async {
        do { try await model.service.setLearnerRecordingEnabled(value) }
        catch { self.error = error.localizedDescription }
    }
    private func remove() async {
        do { try await model.service.removeDeadlineGoal(deckID: deckID); await load() }
        catch { self.error = error.localizedDescription }
    }
}
