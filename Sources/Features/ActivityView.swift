import SwiftUI
import LearningCore
import StudyApplication
import DesignSystem

struct ActivityView: View {
    let model: EngramModel
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var period: ActivityPeriod = .today
    @State private var summary: ActivitySummary?
    @State private var expandedDeck: String?
    @State private var expandedQuestion: String?
    @State private var filter: ActivityCardFilter = .all
    @State private var limit = 20
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var refreshID: String { "\(model.library.revision)-\(period.rawValue)-\(scenePhase == .active)" }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if typeSize.isAccessibilitySize {
                    periodPicker.pickerStyle(.menu)
                } else { periodPicker.pickerStyle(.segmented) }
                if let summary {
                    VStack(spacing: 12) {
                        metric("Cards reviewed", value: summary.reviewedCount)
                        metric("Review attempts", value: summary.attemptCount)
                        Divider()
                        metric("Due now", value: summary.dueCount)
                    }.padding(20).background(palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Memory now").font(theme.font(.section)).accessibilityAddTraits(.isHeader)
                        Text("Estimated recall · target \(Int((model.library.settings.desiredRetention * 100).rounded()))%")
                            .font(.subheadline).foregroundStyle(palette.secondaryText)
                        Text("Memory and due counts reflect now. Review results reflect \(period.rawValue.lowercased()) and your own ratings.")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    if summary.decks.isEmpty {
                        EngramEmptyState(title: "Watch your memory grow", message: "Create a deck and study a few questions to see your progress here.", symbol: "chart.bar.xaxis")
                    }
                    ForEach(summary.decks) { deck in deckRow(deck) }
                    if !model.library.importedReviews.isEmpty {
                        Text("\(model.library.importedReviews.count) imported review records are preserved separately. Review totals here include Engram ratings only.")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                } else { ProgressView("Loading activity…").frame(maxWidth: .infinity) }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .task(id: refreshID) {
            guard scenePhase == .active else { return }
            repeat {
                let result = await model.service.activity(in: model.library, period: period, now: Date())
                guard !Task.isCancelled else { return }
                summary = result
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            } while !Task.isCancelled
        }
        .onChange(of: period) { _, _ in expandedQuestion = nil; limit = 20 }
    }

    private var periodPicker: some View {
        Picker("Review period", selection: $period) {
            ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
    }
    private var questionPicker: some View {
        Picker("Questions", selection: $filter) {
            ForEach(ActivityCardFilter.allCases) { Text($0.rawValue).tag($0) }
        }
    }
    private func metric(_ title: String, value: Int) -> some View {
        HStack { Text(title).foregroundStyle(palette.secondaryText); Spacer(); Text(value, format: .number).font(.headline).monospacedDigit() }
            .accessibilityElement(children: .combine)
    }
    private func color(_ bucket: MemoryBucket) -> Color {
        switch bucket {
        case .atTarget: return palette.anchor
        case .belowTarget: return palette.againInk
        case .learning: return palette.accentInk
        case .unstudied: return palette.hairline
        case .unavailable: return palette.secondaryText
        }
    }
    private func deckRow(_ deck: ActivityDeck) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                expandedDeck = expandedDeck == deck.id ? nil : deck.id
                expandedQuestion = nil; filter = .all; limit = 20
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.title).font(theme.font(.section)).foregroundStyle(palette.primaryText)
                            if !deck.folder.isEmpty { Text(deck.folder).font(.caption).foregroundStyle(palette.secondaryText) }
                            Text("\(deck.questions.count) cards · \(deck.dueCount) due now").font(.subheadline).foregroundStyle(palette.secondaryText)
                        }
                        Spacer(minLength: 12)
                        Image(systemName: expandedDeck == deck.id ? "chevron.up" : "chevron.down").foregroundStyle(palette.secondaryText)
                    }
                    memoryBar(deck)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityValue(expandedDeck == deck.id ? "Expanded" : "Collapsed")
                .accessibilityHint("Show or hide questions")
            // Counts make every segment readable without relying on color or bar width.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend(deck) }
                VStack(alignment: .leading, spacing: 8) { legend(deck) }
            }
            if deck.suspendedCount > 0 {
                Text("\(deck.suspendedCount) suspended cards not included").font(.caption).foregroundStyle(palette.secondaryText)
            }
            if expandedDeck == deck.id {
                Divider()
                Group {
                    if typeSize.isAccessibilitySize { questionPicker.pickerStyle(.menu) }
                    else { questionPicker.pickerStyle(.segmented) }
                }.onChange(of: filter) { _, _ in limit = 20; expandedQuestion = nil }
                let questions = deck.questions.filter { $0.matches(filter) }
                if questions.isEmpty {
                    Text(deck.questions.isEmpty ? "No active cards in this deck." : "No questions match this filter.")
                        .foregroundStyle(palette.secondaryText).padding(.vertical, 12)
                }
                ForEach(questions.prefix(limit)) { question in
                    questionRow(question)
                    Divider()
                }
                if questions.count > limit {
                    Button("Show more (\(questions.count - limit) remaining)") { limit += 20 }
                        .frame(minHeight: 44).frame(maxWidth: .infinity)
                }
            }
        }.padding(20).background(palette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder private func legend(_ deck: ActivityDeck) -> some View {
        ForEach(MemoryBucket.allCases.filter { deck.counts[$0, default: 0] > 0 }) { bucket in
            HStack(spacing: 5) {
                Circle().fill(color(bucket)).frame(width: 7, height: 7).accessibilityHidden(true)
                Text("\(deck.counts[bucket, default: 0]) \(bucket.rawValue.lowercased())").font(.caption)
            }.foregroundStyle(palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func memoryBar(_ deck: ActivityDeck) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(MemoryBucket.allCases) { bucket in
                    if let count = deck.counts[bucket], count > 0 {
                        color(bucket).frame(width: geometry.size.width * Double(count) / Double(max(1, deck.questions.count)))
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).background(palette.hairline).clipShape(Capsule())
        }.frame(height: 10).accessibilityHidden(true)
    }
    private func questionRow(_ question: ActivityQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { expandedQuestion = expandedQuestion == question.id ? nil : question.id } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(question.prompt).font(theme.font(.body)).foregroundStyle(palette.primaryText).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: expandedQuestion == question.id ? "chevron.up" : "chevron.down").font(.caption)
                    }
                    Label(question.outcome, systemImage: outcomeSymbol(question)).font(.subheadline)
                        .foregroundStyle(outcomeColor(question))
                    Text("\(question.attempts.count) \(question.attempts.count == 1 ? "attempt" : "attempts") · \(question.isDue ? "Due now" : question.bucket == .unstudied ? "Not studied yet" : "Not due")")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expandedQuestion == question.id ? "Expanded" : "Collapsed")
            if expandedQuestion == question.id {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Answer").font(.caption.bold()).foregroundStyle(palette.secondaryText)
                    CardContentView(text: question.answer, media: model.library.media)
                    if question.bucket != .unstudied {
                        Text("Next due: \(question.due.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                    }
                    if !question.attempts.isEmpty {
                        Text("Attempts · \(period.rawValue)").font(.caption.bold())
                        ForEach(question.attempts) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.rating.label).font(.subheadline)
                                Text(event.reviewedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(palette.secondaryText)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(palette.canvas, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private func outcomeSymbol(_ question: ActivityQuestion) -> String {
        switch question.attempts.first?.rating { case .again: return "xmark.circle"; case .hard: return "minus.circle"; case .good, .easy: return "checkmark.circle"; case nil: return "circle.dotted" }
    }
    private func outcomeColor(_ question: ActivityQuestion) -> Color {
        switch question.attempts.first?.rating { case .again: return palette.againInk; case .hard: return palette.hardInk; case .good, .easy: return palette.goodInk; case nil: return palette.secondaryText }
    }
}
