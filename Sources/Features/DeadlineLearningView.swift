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
    @Environment(\.engramTheme) private var theme
    var body: some View {
        Form {
            EngramListSection("Deadline learning") {
                Text("Plan your practice around a date and a target.").font(theme.font(.section))
                Text("Experimental · estimates use provisional learning assumptions, not calibrated exam predictions.").font(.caption).engramSecondaryText()
                DatePicker("Learn by", selection: $deadline, in: Date()...Date().addingTimeInterval(366 * 86400), displayedComponents: .date)
                Stepper("Target performance · \(Int(target))%", value: $target, in: 10...99)
                Stepper("Daily study budget · \(minutes) min", value: $minutes, in: 1...120)
                Button(record == nil ? "Create study plan" : "Save goal & refresh target cards") {
                    if record == nil { Task { await save() } } else { confirmReset = true }
                }.disabled(working || !loaded)
                Text("Saving freezes the current eligible cards as the target set. Updating the goal replaces this set and starts a new forecast history.").font(.caption).engramSecondaryText()
            }
            if let error { EngramListSection { Text(error).foregroundStyle(.red) } }
            if let record, let plan {
                EngramListSection("Deadline forecast") {
                    LabeledContent("Target", value: record.goal.target.formatted(.percent))
                    LabeledContent("With this plan", value: plan.forecast.formatted(.percent))
                    LabeledContent("Without further practice", value: plan.baseline.formatted(.percent))
                    LabeledContent("Planned study time", value: "\(plan.plannedMinutes) min")
                    LabeledContent("Target cards", value: "\(record.goal.items.count)")
                    if record.goal.deadline <= Date() { Text("Deadline passed. Set a future date to plan again.").font(.caption) }
                    else if plan.staleItems > 0 { Text("\(plan.staleItems) target cards changed or became unavailable. Refresh the target set to plan again.").font(.caption) }
                    else if plan.forecast < record.goal.target { Text("The prototype did not find a plan reaching your target within its budget and search limits.").font(.caption) }
                    Text("This is expected performance on your target cards, not a guaranteed test mark. Review gains, new-card knowledge and half-lives are unvalidated assumptions. Actual outcomes may differ substantially.").font(.caption).engramSecondaryText()
                    Button("Recalculate & save forecast") { Task { await recalculate() } }.disabled(working)
                }
                EngramListSection("Practice plan") {
                    let today = plan.actions.filter { $0.date <= Date() }
                    if today.isEmpty { Text("No practice planned right now.") }
                    else {
                        Button("Study \(today.count) planned cards") { Task { await start() } }
                            .disabled(working || plan.staleItems > 0 || record.goal.deadline <= Date())
                    }
                    let dates = Array(Set(plan.actions.map(\.date))).sorted()
                    ForEach(Array(dates.prefix(14)), id: \.self) { date in
                        let actions = plan.actions.filter { $0.date == date }
                        LabeledContent(date.formatted(date: .abbreviated, time: .omitted), value: "\(actions.count) cards · \(Int(ceil(actions.reduce(0) { $0 + $1.seconds } / 60))) min")
                    }
                    if dates.count > 14 { Text("\(dates.count - 14) more study days in the exported plan.").font(.caption) }
                    Text("Recommendations are optional. Recalculate after studying; FSRS schedules are updated normally when you answer a card.").font(.caption).engramSecondaryText()
                }
                EngramListSection("Observations") {
                    LabeledContent("Accepted unaided answers", value: String(plan.observations))
                    LabeledContent("Correct answers", value: String(plan.observedCorrect))
                    LabeledContent("Measured active time", value: "\(Int(plan.timedSeconds / 60)) min")
                    ForEach(Array(Set(record.goal.items.map(\.questionType))).sorted(), id: \.self) { type in
                        LabeledContent(type, value: "\(record.goal.items.filter { $0.questionType == type }.count) target cards")
                    }
                    Text("Only accepted, unassisted, objectively graded answers matching target question versions inform this model. Manual ratings and missing assistance remain excluded.").font(.caption).engramSecondaryText()
                    Toggle("Record learner evidence on this device", isOn: $recording)
                        .onChange(of: recording) { _, value in Task { await setRecording(value) } }
                    Text("This is the existing library-wide local learner-recording preference, separate from research consent and cloud uploads.").font(.caption).engramSecondaryText()
                }
                EngramListSection("Forecast history") {
                    if record.forecasts.count > 1 {
                        Chart {
                            ForEach(Array(record.forecasts.enumerated()), id: \.offset) { _, forecast in
                                LineMark(x: .value("Saved", forecast.generatedAt), y: .value("Forecast", forecast.forecast * 100))
                            }
                            RuleMark(y: .value("Target", record.goal.target * 100)).lineStyle(StrokeStyle(dash: [4, 4]))
                        }.chartYScale(domain: 0...100).frame(height: 180).accessibilityLabel("Saved deadline performance forecasts, percent")
                    }
                    Text("\(record.forecasts.count) saved forecasts · evidence revision \(plan.evidenceRevision)").font(.caption)
                    Text(plan.policyVersion).font(.caption).engramSecondaryText()
                    Text("Forecasts show how predictions changed, not measured mastery. Up to 100 snapshots are kept locally per notebook.").font(.caption).engramSecondaryText()
                    if let data = try? JSONEncoder().encode(plan), let json = String(data: data, encoding: .utf8) {
                        ShareLink("Export current plan & metrics", item: json)
                    }
                    Button("Remove deadline goal", role: .destructive) { Task { await remove() } }.disabled(working)
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
            let saved = try await model.service.deadlineRecord(deckID: deckID)
            let forecast = saved == nil ? nil : try await model.service.deadlinePlan(deckID: deckID)
            let status = try await model.service.learnerStatus()
            guard account == model.understanding.account(model), library == model.activeLibraryID else { return }
            record = saved; plan = forecast; recording = status.recordingEnabled
            if let saved { deadline = saved.goal.deadline; target = saved.goal.target * 100; minutes = saved.goal.dailyMinutes }
            error = nil; loaded = true
        } catch { self.error = error.localizedDescription; loaded = true }
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
