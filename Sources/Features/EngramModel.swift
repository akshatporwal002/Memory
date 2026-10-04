import Foundation
import Observation
import LearningCore
import StudyApplication
import DesignSystem
import ChatGPTAuth
import PersistenceAdapters

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
    public let reminders: ReviewReminderController
    let voice = VoiceStudyController()
    let voiceWork = VoiceProcessingController()
    let aiMarker = AIAnswerMarker()
    let pdfLearning = PDFLearningController()
    let cloud: CloudAccountController
    let assistant = AssistantController()
    let typedAnswer = TypedAnswerController()
    let deferredReview = DeferredReviewController()
    let tutor = TutorController()
    let research = ResearchController()
    /// Non-production namespace for isolated UI fixtures; never set in release.
    public var testingScope: String?
    var pendingAttempt: AnswerAttempt? {
        guard let id = library.session?.current?.presentationID else { return nil }
        return library.answerAttempts?.last { $0.presentationID == id && $0.committedAt == nil }
    }
    public var settingsRoute: String?
    public var portabilityRequested = false
    var actionReviewPresented = false
    var cloudAccountPresented = false
    var sharingDeckID: String?
    var memoryPresented = false
    var pdfLearningPresented = false
    var pdfFilePickerRequested = false
    public var answerFeedback: String?
    public var markingAnswer = false
    public let chatGPT = ChatGPTConnection.live()
    public let service: StudyService
    public private(set) var library = LibrarySnapshot()
    public private(set) var librarySpaces = LibrarySpaceCatalog().spaces
    public private(set) var activeLibraryID = LibrarySpace.defaultID
    public private(set) var libraryPresentationEpoch = UUID()
    private var librarySelectionRestored = false
    public var activeLibraryName: String { librarySpaces.first { $0.id == activeLibraryID }?.name ?? "My library" }
    private var librarySelectionKey: String { "engram.activeLibrary." + (cloud.userID?.uuidString.lowercased() ?? cloud.localProfileID ?? "local") }
    private var creationDraftKey: String {
        let account = cloud.userID?.uuidString.lowercased() ?? cloud.localProfileID ?? "local"
        return account == "local" && activeLibraryID == LibrarySpace.defaultID ? "engram.deckCreationDraft.v1" : "engram.deckCreationDraft.v1." + account + "." + activeLibraryID
    }
    private func refreshLibraryPresentation() {
        libraryPresentationEpoch = UUID()
        selectedDeckID = nil; libraryDeckRequest = nil; search = ""
        activeDeckOverviewID = nil; activeContentDeckID = nil; activeContentKind = nil
        notebookDeckID = nil; questionsDeckID = nil; visibleLibraryDocumentID = nil
        notebookFocusNoteID = nil; notebookFocusBlockID = nil; selectedNoteID = nil; selectedCardID = nil
        reviewPresented = false; reviewChoiceSelection = nil; answerFeedback = nil
        typedAnswer.error = nil; typedAnswer.proposedAnswer = nil
        creationPresented = false; editorPresented = false; draft = nil; deckForm = nil; deleteDeck = nil; deleteNote = nil
        pdfLearning.selectLibrary(accountID: cloud.userID?.uuidString.lowercased() ?? cloud.localProfileID, libraryID: activeLibraryID)
        deckCreationDraft = defaults.data(forKey: creationDraftKey).flatMap { try? JSONDecoder().decode(DeckCreationDraft.self, from: $0) } ?? DeckCreationDraft()
    }
    public func restoreLibrarySelection() async {
        voice.stop(); await voiceWork.pause()
        aiMarker.personal.selectAccount(cloud.userID?.uuidString.lowercased() ?? cloud.localProfileID ?? "local")
        aiMarker.invalidateCatalog()
        do {
            librarySpaces = try await service.librarySpaces()
            let remembered = defaults.string(forKey: librarySelectionKey) ?? LibrarySpace.defaultID
            let id = librarySpaces.contains(where: { $0.id == remembered }) ? remembered : LibrarySpace.defaultID
            let resetPresentation = librarySelectionRestored || id != LibrarySpace.defaultID || cloud.signedIn
            try await service.selectLibrary(id); activeLibraryID = id; librarySelectionRestored = true
            if resetPresentation { refreshLibraryPresentation() }
        } catch { self.error = error.localizedDescription }
    }
    public func selectLibrary(_ id: String) async {
        guard id != activeLibraryID else { return }
        guard !busy, !typedAnswer.busy, !markingAnswer, !cloud.busy, !voiceWork.capturing else { error = "Finish the current edit or answer review before switching libraries."; return }
        busy = true; defer { busy = false }
        await assistant.stopAndWait(); voice.stop(); await voiceWork.pause(); pdfLearning.cancel()
        do {
            try await service.selectLibrary(id)
            library = try await service.snapshot(); activeLibraryID = id
            defaults.set(id, forKey: librarySelectionKey)
            refreshLibraryPresentation()
            librarySpaces = try await service.librarySpaces(); now = Date()
            await voiceWork.resume(model: self)
        } catch { self.error = error.localizedDescription }
    }
    public func createLibrary(name: String, deviceOnly: Bool) async {
        guard !busy, !typedAnswer.busy, !cloud.busy else { return }
        error = nil; busy = true
        do {
            let space = try await service.createLibrary(name: name, deviceOnly: deviceOnly)
            librarySpaces = try await service.librarySpaces()
            busy = false
            await selectLibrary(space.id)
        } catch { busy = false; self.error = error.localizedDescription }
    }
    public func moveDeckToLibrary(_ id: String, libraryID: String) async {
        guard !busy, !typedAnswer.busy, !cloud.busy else { return }
        await assistant.stopAndWait(); voice.stop()
        _ = await perform { try await $0.moveDeckToLibrary(id, libraryID: libraryID) }
    }
    public private(set) var loaded = false
    public private(set) var busy = false
    public var error: String?
    public var destination: EngramDestination = .today
    public var selectedDeckID: String?
    public var libraryDeckRequest: String?
    public var coverPickerDeckID: String?
    public var deckCreationDraft: DeckCreationDraft {
        didSet {
            if let data = try? JSONEncoder().encode(deckCreationDraft) {
                defaults.set(data, forKey: creationDraftKey)
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
    public var visibleNotebookBlockID: String?
    public var visibleQuestionID: String?
    public var visibleLibraryDocumentID: String?
    public var selectedNoteID: String?
    public var selectedCardID: String?
    /// Presentation-only memory prevents replaying the completion flourish on sheet re-entry.
    public var animatedCompletionSessions: Set<String> = []
    /// Keep unsubmitted selection through adaptive navigation rebuilds, scoped to one presentation.
    var reviewChoiceSelection: (presentationID: String, choiceID: String)?
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

    public init(service: StudyService, defaults: UserDefaults = .standard, repository: SQLiteLibraryRepository? = nil) {
        self.service = service; self.defaults = defaults
        reminders = ReviewReminderController(defaults: defaults)
        cloud = CloudAccountController(repository:repository)
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
        if !librarySelectionRestored { await restoreLibrarySelection() }
        do {
            library = try await service.snapshot(); now = Date(); loaded = true
            librarySpaces = try await service.librarySpaces()
            if let value = library.assistantState?.preferences?["theme"],let choice = EngramTheme(rawValue:value) { theme = choice }
            if let value = library.assistantState?.preferences?["appearance"],let choice = EngramAppearance(rawValue:value) { appearance = choice }
        }
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
        guard !(library.voiceJobs ?? []).contains(where: { $0.attempt.presentationID == presentationID && $0.state != .cancelled }) else { return }
        _ = await perform { service in
            if self.pendingAttempt != nil { try await service.markAttemptAssisted(presentationID: presentationID) }
            _ = try await service.reveal(sessionID: sessionID, presentationID: presentationID, now: Date()) }
    }
    public func grade(_ rating: Grade, sessionID: String, presentationID: String) async {
        guard !(library.voiceJobs ?? []).contains(where: { $0.attempt.presentationID == presentationID && $0.state != .cancelled }) else { return }
        // Stable presentation-derived mutation ID supports retry after uncertain completion.
        _ = await perform { try await $0.grade(sessionID: sessionID, presentationID: presentationID,
            rating: rating, mutationID: "grade-" + presentationID, now: Date()) }
    }
    public func undo() async {
        guard let session = library.session else { return }
        _ = await perform { try await $0.undo(sessionID: session.id, now: Date()) }
    }
    func submitChoice(_ choice: String, presentationID: String) async {
        guard !(library.voiceJobs ?? []).contains(where: { $0.attempt.presentationID == presentationID && $0.state != .cancelled }) else { return }
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
        if let job = voiceWork.jobs(self).first(where: { $0.attempt.presentationID == item.presentationID && $0.state == .completed }) {
            await voiceWork.advanceCompleted(job, model: self); return
        }
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
