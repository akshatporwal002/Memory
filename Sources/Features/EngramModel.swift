import Foundation
import Observation
import LearningCore
import StudyApplication
import DesignSystem
import ChatGPTAuth

public enum EngramDestination: String, CaseIterable, Identifiable { case today, library, activity
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String { switch self { case .today: return "sun.max"; case .library: return "rectangle.stack"; case .activity: return "chart.bar.xaxis" } }
}
public struct DeckForm: Identifiable {
    public let id = UUID()
    public var deckID: String?
    public var name: String
    public init(deck: Deck? = nil) { deckID = deck?.id; name = deck?.name ?? "" }
}

/// Own once in the composition root. Theme, selection and sheets never own learning data.
@MainActor @Observable public final class EngramModel {
    let voice = VoiceStudyController()
    let aiMarker = AIAnswerMarker()
    let pdfLearning = PDFLearningController()
    var pdfLearningPresented = false
    public var answerFeedback: String?
    public var markingAnswer = false
    public let chatGPT = ChatGPTConnection.live()
    public let service: StudyService
    public private(set) var library = LibrarySnapshot()
    public private(set) var loaded = false
    public private(set) var busy = false
    public var error: String?
    public var destination: EngramDestination = .today
    public var selectedDeckID: String?
    public var libraryDeckRequest: String?
    public var deckCreationDraft: DeckCreationDraft {
        didSet {
            if let data = try? JSONEncoder().encode(deckCreationDraft) {
                defaults.set(data, forKey: "engram.deckCreationDraft.v1")
            }
        }
    }
    public var creationPresented = false
    public var notebookFocusNoteID: String?
    public var notebookFocusBlockID: String?
    public var notebookDeckID: String?
    public var notebookWritingOnly = false
    public var questionsDeckID: String?
    public var activeDeckOverviewID: String?
    public var activeContentDeckID: String?
    public var activeContentKind: String?
    public var selectedNoteID: String?
    public var selectedCardID: String?
    /// Presentation-only memory prevents replaying the completion flourish on sheet re-entry.
    public var animatedCompletionSessions: Set<String> = []
    public var search = ""
    public var draft: NoteDraft?
    public var editorPresented = false
    public var reviewPresented = false
    public var settingsPresented = false
    public var deckForm: DeckForm?
    public var deleteDeck: Deck?
    public var deleteNote: Note?
    public var theme: EngramTheme { didSet { defaults.set(theme.rawValue, forKey: "engram.theme.v1") } }
    public var appearance: EngramAppearance { didSet { defaults.set(appearance.rawValue, forKey: "engram.appearance.v1") } }
    public private(set) var lastBackupExport: Date?
    public func recordBackupExport(at date: Date = Date()) {
        lastBackupExport = date
        defaults.set(date, forKey: "engram.lastBackupExport.v1")
    }
    public private(set) var now = Date()
    @ObservationIgnored private let defaults: UserDefaults

    public init(service: StudyService, defaults: UserDefaults = .standard) {
        self.service = service; self.defaults = defaults
        lastBackupExport = defaults.object(forKey: "engram.lastBackupExport.v1") as? Date
        deckCreationDraft = defaults.data(forKey: "engram.deckCreationDraft.v1")
            .flatMap { try? JSONDecoder().decode(DeckCreationDraft.self, from: $0) } ?? DeckCreationDraft()
        theme = EngramTheme(rawValue: defaults.string(forKey: "engram.theme.v1") ?? "") ?? .warm
        appearance = EngramAppearance(rawValue: defaults.string(forKey: "engram.appearance.v1") ?? "") ?? .system
        if ProcessInfo.processInfo.arguments.contains("--prepare-local-voice") {
            Task { await voice.prepare() }
        }
    }
    func notebookDraft(_ deckID: String) -> NotebookEditingDraft? {
        defaults.data(forKey: "engram.notebookDraft." + deckID).flatMap { try? JSONDecoder().decode(NotebookEditingDraft.self, from: $0) }
    }
    func keepNotebookDraft(_ draft: NotebookEditingDraft?, deckID: String) {
        let key = "engram.notebookDraft." + deckID
        if let draft, let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }
    public var due: [StudyCard] { QueuePolicy.dueCards(in: library, deckID: nil, now: now) }
    public func due(in deck: Deck) -> [StudyCard] { QueuePolicy.dueCards(in: library, deckID: deck.id, now: now) }
    public var todaysReviews: [ReviewEvent] {
        let start = QueuePolicy.dayStart(now: now, settings: library.settings)
        return library.activeReviews.filter { $0.reviewedAt >= start && $0.reviewedAt <= now }
    }
    public var visibleNotes: [Note] { StudyService.search(search, deckID: selectedDeckID, in: library) }
    public func deckName(_ id: String) -> String { library.decks.first { $0.id == id }?.name ?? "Deleted deck" }
    public func cards(for note: Note) -> [StudyCard] { library.liveCards.filter { $0.noteID == note.id }.sorted { $0.ordinal < $1.ordinal } }
    public var canUndo: Bool {
        guard let id = library.session?.id else { return false }
        return library.activeReviews.contains { $0.sessionID == id }
    }
    public func refresh() async {
        guard !busy else { return }
        do { library = try await service.snapshot(); now = Date(); loaded = true }
        catch { self.error = error.localizedDescription }
    }
    @discardableResult public func perform(_ operation: (StudyService) async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await operation(service)
            library = try await service.snapshot(); now = Date(); loaded = true
            if !library.liveDecks.contains(where: { $0.id == selectedDeckID }) { selectedDeckID = nil }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    public func beginReview(deckID: String? = nil) async {
        if await perform({ _ = try await $0.startSession(deckID: deckID, now: Date()) }) { reviewPresented = true }
    }
    public func resumeReview() async {
        if await perform({ _ = try await $0.refreshSession(now: Date()) }) { reviewPresented = true }
    }
    public func reveal(sessionID: String, presentationID: String) async {
        _ = await perform { _ = try await $0.reveal(sessionID: sessionID, presentationID: presentationID, now: Date()) }
    }
    public func grade(_ rating: Grade, sessionID: String, presentationID: String) async {
        // Stable presentation-derived mutation ID supports retry after uncertain completion.
        _ = await perform { try await $0.grade(sessionID: sessionID, presentationID: presentationID,
            rating: rating, mutationID: "grade-" + presentationID, now: Date()) }
    }
    public func undo() async {
        guard let session = library.session else { return }
        _ = await perform { try await $0.undo(sessionID: session.id, now: Date()) }
    }
    func submitChoice(_ choice: String, presentationID: String) async {
        guard let session = library.session, session.current?.presentationID == presentationID else { return }
        _ = await perform { try await $0.submitAnswer(sessionID: session.id, presentationID: presentationID, choiceID: choice) }
    }
    func markSpokenAnswer(_ text: String) async {
        guard !markingAnswer, let session = library.session, let item = session.current, item.revealedAt == nil,
              let note = library.liveNotes.first(where: { $0.id == item.card.noteID }) else { return }
        answerFeedback = nil
        if let question = note.mcq {
            guard let choice = question.ordered(for: item.presentationID).resolvePresented(text) else { answerFeedback = "Please say one option letter or its answer text."; return }
            await submitChoice(choice, presentationID: item.presentationID); return
        }
        markingAnswer = true; defer { markingAnswer = false }
        do {
            let card = try CardRenderer.render(note: note, card: item.card, revealed: true)
            let question = try CardRenderer.render(note: note, card: item.card, revealed: false)
            let assessment = try await aiMarker.assess(answer: text, note: note, prompt: question.prompt, expected: card.answer ?? note.back, library: library, connection: chatGPT)
            try Task.checkCancellation()
            guard library.session?.current?.presentationID == item.presentationID, library.session?.current?.revealedAt == nil else { return }
            if assessment.outcome == .unclear { answerFeedback = assessment.reason; return }
            _ = await perform { try await $0.submitAnswer(sessionID: session.id, presentationID: item.presentationID, assessment: assessment) }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { answerFeedback = error.localizedDescription } }
    }
    func nextAnswer() async {
        guard let session = library.session, let item = session.current else { return }
        answerFeedback = nil
        _ = await perform { try await $0.nextAssessedAnswer(sessionID: session.id, presentationID: item.presentationID) }
    }
    func skipAnswer() async {
        guard let session = library.session, let item = session.current else { return }
        answerFeedback = nil
        _ = await perform { try await $0.skipAnswer(sessionID: session.id, presentationID: item.presentationID) }
    }
    public func newNote(deckID: String? = nil) {
        guard let id = deckID ?? selectedDeckID ?? library.liveDecks.first?.id else { creationPresented = true; return }
        draft = NoteDraft(deckID: id); editorPresented = true; error = nil
    }
    public func edit(_ note: Note) {
        error = nil
        if NotebookDocument.supports(note), let deck = library.liveDecks.first(where: { $0.id == note.deckID }),
           deck.sourceDocument != nil || deck.notebookBlocks != nil {
            notebookWritingOnly = false; notebookFocusNoteID = note.id; notebookDeckID = deck.id
        } else { draft = NoteDraft(note: note); editorPresented = true }
    }
    public func saveDraft() async {
        guard let draft else { return }
        if await perform({ _ = try await $0.saveNote(draft, now: Date()) }) { editorPresented = false; self.draft = nil }
    }
}
