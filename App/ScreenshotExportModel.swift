import SwiftUI
import Observation
import Features
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import AnkiAdapters
#if os(iOS)
import Photos
#endif

@MainActor @Observable final class ScreenshotExportModel {
    var presented = false
    var touring = false
    var running = false
    var hidingProgress = false
    var progress = ""
    var error: String?
    var document: ScreenshotZipDocument?
    var imageCount = 0
    var filename = "Engram-screenshots"
    var captureNotes: [String] = []
    #if os(iOS)
    private var photos: [String: Data] = [:]
    var savingPhotos = false
    var savedToPhotos = false
    #endif
    var copy: EngramModel?
    var transfer: PortabilityModel?
    var portabilityPresented = false
    var editorPreview = false
    var acknowledgements = false
    let capture = NativeScreenCapture()
    @ObservationIgnored private var task: Task<Void, Never>?

    func prepare() {
        guard !running else { return }
        resetPhotos()
        document = nil; error = nil; imageCount = 0; presented = true
        captureNotes = []
    }

    func start(source: EngramModel) {
        guard !running, source.loaded, !source.busy else { return }
        running = true
        resetPhotos()
        presented = false; document = nil; error = nil; imageCount = 0
        task = Task { await run(source: source) }
    }

    func cancel() { task?.cancel() }

    private func resetPhotos() {
        #if os(iOS)
        photos = [:]; savedToPhotos = false
        #endif
    }

    #if os(iOS)
    func saveToPhotos() async {
        guard !savingPhotos, !savedToPhotos, !photos.isEmpty else { return }
        savingPhotos = true; error = nil
        defer { savingPhotos = false }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            error = status == .restricted
                ? "Saving photos is restricted on this device. Your screenshots have not been saved."
                : "Allow Engram to add photos in Settings, then try Save to Photos again. Your screenshots are still ready."
            return
        }
        let entries = photos.sorted { $0.key < $1.key }
        let capturedAt = Date()
        do {
            // One Photos transaction; no reading, fetching or modifying existing assets.
            try await PHPhotoLibrary.shared().performChanges {
                for (index, entry) in entries.enumerated() {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = capturedAt.addingTimeInterval(Double(index) / 1_000)
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = entry.key
                    options.uniformTypeIdentifier = "public.png"
                    request.addResource(with: .photo, data: entry.value, options: options)
                }
            }
            savedToPhotos = true
            photos = [:]
        } catch {
            self.error = "Could not save screenshots to Photos. You can retry. \(error.localizedDescription)"
        }
    }
    #endif

    private func run(source: EngramModel) async {
        // Never pass the persistent service into a capture screen. Even review/reveal
        // actions and incidental view tasks can only reach this MemoryRepository.
        let domain = "engram.screenshot." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: domain) else {
            error = "Could not create an isolated capture session."; presented = true; running = false; return
        }
        let model = EngramModel(service: StudyService(repository: MemoryRepository(initial: source.library), scheduler: FSRSScheduler()), defaults: defaults)
        model.theme = source.theme; model.appearance = source.appearance
        await model.refresh()
        copy = model
        transfer = PortabilityModel(model: model, backupDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var images: [String: Data] = [:]
        var notes: [String] = [
            "Actual app views using an isolated in-memory copy. No saved cards, settings or study progress were changed.",
            "Representative screens, not every card/deck, menu, alert or import-error state. Existing theme and system text size retained.",
            "Long main scroll areas are captured in overlapping viewport images (up to 12 per screen). Secondary panes and nested text editors are not exhaustively scrolled.",
            "May contain private card text, deck names and media. Nothing is uploaded automatically."
        ]
        do {
            // Allow the consent sheet to finish dismissing before mounting the tour.
            try await settle(milliseconds: 700)
            touring = true
            try await settle()
            for destination in EngramDestination.allCases {
                model.destination = destination
                try await collect(destination.rawValue, images: &images, notes: &notes)
            }
            model.destination = .library
            if let deck = model.library.liveDecks.first {
                model.selectedDeckID = deck.id
                if let note = model.visibleNotes.first {
                    model.selectedNoteID = note.id
                    model.selectedCardID = model.cards(for: note).first?.id
                }
                try await collect("deck-detail", images: &images, notes: &notes)
            } else { notes.append("Deck detail and card editors skipped: the library has no decks.") }

            model.deckForm = DeckForm()
            try await collect("new-deck", images: &images, notes: &notes)
            model.deckForm = nil
            try await settle()
            if let deck = model.library.liveDecks.first {
                model.deckForm = DeckForm(deck: deck)
                try await collect("rename-deck", images: &images, notes: &notes)
                model.deckForm = nil
                try await settle()
                model.newNote(deckID: deck.id)
                try await collect("new-card-basic", images: &images, notes: &notes)
                model.draft?.kind = .cloze
                try await collect("new-card-cloze", images: &images, notes: &notes)
                model.editorPresented = false; model.draft = nil
                try await settle()
                if let note = model.library.liveNotes.first {
                    model.edit(note)
                    try await collect("edit-card", images: &images, notes: &notes)
                    editorPreview = true
                    try await collect("card-preview", images: &images, notes: &notes)
                    model.editorPresented = false; model.draft = nil; editorPreview = false
                    try await settle()
                }
            }
            model.settingsPresented = true
            try await collect("settings", images: &images, notes: &notes)
            acknowledgements = true
            try await collect("acknowledgements", images: &images, notes: &notes)
            acknowledgements = false
            model.settingsPresented = false
            try await settle()
            portabilityPresented = true
            try await collect("import-export", images: &images, notes: &notes)
            portabilityPresented = false
            try await settle()
            await model.beginReview()
            guard model.error == nil else { throw EngramError.invalid(model.error ?? "Could not open review.") }
            try await collect(model.library.session?.current == nil ? "review-empty" : "review-question", images: &images, notes: &notes)
            if let session = model.library.session, let item = session.current {
                await model.reveal(sessionID: session.id, presentationID: item.presentationID)
                guard model.error == nil else { throw EngramError.invalid(model.error ?? "Could not reveal review.") }
                try await collect("review-answer", images: &images, notes: &notes)
            } else { notes.append("Review question/answer skipped: no study cards are available. Captured the actual empty review state.") }
            model.reviewPresented = false
            try await settle()
            try Task.checkCancellation()
            #if os(iOS)
            progress = "Preparing photos…"
            photos = images
            #else
            progress = "Preparing screenshot ZIP…"
            let manifest = ScreenshotManifest(createdAt: Date(), theme: source.theme.rawValue,
                appearance: source.appearance.rawValue, files: images.keys.sorted(), notes: notes)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            let metadata = try encoder.encode(manifest)
            let entries = images
            let bytes = try await Task.detached(priority: .userInitiated) {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EngramCapture-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("screenshots.zip")
                try ScreenshotArchive.write(images: entries, manifest: metadata, to: url)
                return try Data(contentsOf: url)
            }.value
            try Task.checkCancellation()
            document = ScreenshotZipDocument(bytes: bytes)
            filename = "Engram-screenshots-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            #endif
            imageCount = images.count
            captureNotes = notes
        } catch is CancellationError {
            error = "Capture cancelled. Your library and original screen were left unchanged."
        } catch { self.error = "Screenshot capture failed. No screenshots were saved. \(error.localizedDescription)" }
        model.settingsPresented = false; model.reviewPresented = false; model.editorPresented = false; model.deckForm = nil
        portabilityPresented = false; touring = false; hidingProgress = false
        copy = nil; transfer = nil
        acknowledgements = false; editorPreview = false
        defaults.removePersistentDomain(forName: domain)
        // Also allows any captured sheet to disappear before showing the result.
        try? await Task.sleep(for: .milliseconds(500))
        presented = true; task = nil; running = false
    }

    private func collect(_ name: String, images: inout [String: Data], notes: inout [String]) async throws {
        progress = "Capturing \(name.replacingOccurrences(of: "-", with: " "))…"
        try await settle()
        capture.scrollToTop()
        try await settle(milliseconds: 250)
        for page in 1...12 {
            try Task.checkCancellation()
            hidingProgress = true
            try await settle(milliseconds: 120)
            let data = try await capture.png()
            hidingProgress = false
            guard images.count < 100, images.values.reduce(data.count, { $0 + $1.count }) <= 100 * 1_024 * 1_024 else {
                throw EngramError.invalid("Capture exceeded 100 images or 100 MB. Try a smaller window or library.")
            }
            let file = String(format: "%03d-%@-%02d.png", images.count + 1, name, page)
            images[file] = data
            guard capture.scrollForward() else { break }
            if page == 12 { notes.append("\(name): stopped after 12 viewport images; additional content was not captured.") }
            try await settle(milliseconds: 250)
        }
    }

    private func settle(milliseconds: Int = 600) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
        try Task.checkCancellation()
    }
}

private struct ScreenshotManifest: Encodable {
    let format = "engram-ui-screenshots-v1"
    let createdAt: Date
    let theme: String
    let appearance: String
    let platform = ProcessInfo.processInfo.operatingSystemVersionString
    let files: [String]
    let notes: [String]
}
