import SwiftUI
import Features
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import DesignSystem
import LearningCore
import AnkiAdapters
import UniformTypeIdentifiers

@main
struct EngramApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Engram", id: "engram-library") {
            ApplicationRoot().frame(minWidth: 480, minHeight: 580)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) { } }
        #else
        WindowGroup { ApplicationRoot() }
        #endif
    }
}

/// The only production composition root; one service/repository instance per scene.
/// iOS scene creation is explicitly limited in Info.plist and macOS uses a single Window.
private struct ApplicationRoot: View {
    @State private var model: EngramModel?
    @State private var transfer: PortabilityModel?
    @State private var portabilityPresented = false
    @State private var failure: String?
    @State private var choosingRecoveryBackup = false
    @State private var recoveryCandidate: LibrarySnapshot?
    @State private var recoveryOriginal: Data?
    @State private var recoveryTarget: URL?
    @State private var recoveryBusy = false
    @State private var recoveryError: String?
    @State private var confirmRecovery = false
    @State private var recoveryNotice: String?
    var body: some View {
        Group {
            if let model { EngramRootView(model: model, portabilityAction: { portabilityPresented = true }) }
            else if let failure {
                ScrollView { VStack(spacing: EngramSpacing.section) {
                    EngramEmptyState(title: "Your library could not open", message: failure, symbol: "externaldrive.badge.exclamationmark")
                    Text("Your saved file has not been reset. Recovery validates a complete Engram backup and preserves the unreadable original before replacement.")
                    if recoveryBusy { ProgressView("Preparing recovery…") }
                    if let recoveryError { EngramInlineError(message: recoveryError) }
                    Button("Try opening again") { Task { await openLibrary() } }.buttonStyle(EngramButtonStyle()).disabled(recoveryBusy)
                    Button("Choose a complete backup to restore…") { choosingRecoveryBackup = true }
                        .buttonStyle(EngramButtonStyle(.secondary)).disabled(recoveryBusy)
                    if let candidate = recoveryCandidate {
                        Text("Backup inspected: \(candidate.liveDecks.count) decks, \(candidate.liveCards.count) cards, \(candidate.media.count) media files and \(candidate.reviews.count + candidate.importedReviews.count) review records.")
                        Text("Restoring makes this backup the active library on this device. The current unreadable file is retained separately.")
                        Button("Restore inspected backup…", role: .destructive) { confirmRecovery = true }
                            .buttonStyle(EngramButtonStyle(.destructive)).disabled(recoveryBusy)
                        Button("Cancel recovery", role: .cancel) { clearRecoveryInspection() }.disabled(recoveryBusy)
                    }
                }.padding(EngramSpacing.section).frame(maxWidth: 720).frame(maxWidth: .infinity) }.engramCanvas()
            } else { ProgressView("Opening Engram…") }
        }
        .sheet(isPresented: $portabilityPresented) { if let transfer { PortabilityView(transfer: transfer) } }
        .fileImporter(isPresented: $choosingRecoveryBackup, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { Task { await inspectRecoveryBackup(url) } }
            case .failure(let error): recoveryError = error.localizedDescription
            }
        }
        .confirmationDialog("Restore this complete backup?", isPresented: $confirmRecovery, titleVisibility: .visible) {
            Button("Preserve original and restore", role: .destructive) { Task { await performRecovery() } }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The backup becomes your active library. Recovery stops if the original file cannot be preserved or has changed since inspection. This does not change the selected backup file.") }
        .alert("Library recovered", isPresented: Binding(get: { recoveryNotice != nil }, set: { if !$0 { recoveryNotice = nil } })) {
            Button("OK") { recoveryNotice = nil }
        } message: { Text(recoveryNotice ?? "") }
        .task { if model == nil { await openLibrary() } }
    }
    private func libraryLocation() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Engram", isDirectory: true).appendingPathComponent("library.json")
    }
    @MainActor private func openLibrary() async {
        failure = nil
        do {
            let location = try libraryLocation()
            let repository = try await Task.detached(priority: .userInitiated) { try AtomicFileRepository(url: location) }.value
            let opened = EngramModel(service: StudyService(repository: repository, scheduler: FSRSScheduler()))
            model = opened
            transfer = PortabilityModel(model: opened, backupDirectory: location.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true))
            failure = nil
        } catch { failure = error.localizedDescription }
    }
    @MainActor private func inspectRecoveryBackup(_ url: URL) async {
        guard !recoveryBusy else { return }
        recoveryBusy = true; recoveryError = nil; clearRecoveryInspection()
        defer { recoveryBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let target = try libraryLocation()
            let inspection = try await Task.detached(priority: .userInitiated) {
                let candidate = try NativeBackupAdapter.read(from: url)
                try LibraryValidation.validate(candidate)
                let original = FileManager.default.fileExists(atPath: target.path) ? try Data(contentsOf: target) : nil
                return StartupRecoveryInspection(candidate: candidate, original: original)
            }.value
            recoveryCandidate = inspection.candidate; recoveryOriginal = inspection.original; recoveryTarget = target
        } catch { recoveryError = "Recovery inspection failed. The saved library was not changed. \(error.localizedDescription)" }
    }
    @MainActor private func performRecovery() async {
        guard !recoveryBusy, let candidate = recoveryCandidate, let target = recoveryTarget else { return }
        recoveryBusy = true; recoveryError = nil
        defer { recoveryBusy = false }
        let original = recoveryOriginal
        do {
            let preserved = try await Task.detached(priority: .userInitiated) {
                try StartupLibraryRecovery.restore(candidate, to: target, expectedOriginal: original,
                    preservingOriginalIn: target.deletingLastPathComponent().appendingPathComponent("Recovery originals", isDirectory: true))
            }.value
            clearRecoveryInspection()
            await openLibrary()
            if model != nil {
                recoveryNotice = preserved.map { "Your backup is now active. The unreadable original was preserved at:\n\($0.path)" }
                    ?? "Your backup is now the active library. There was no previous library file to preserve."
            } else { recoveryError = "The restored file could not reopen. Any previous original remains in Recovery originals." }
        } catch { recoveryError = "Recovery did not replace the library. \(error.localizedDescription)" }
    }
    private func clearRecoveryInspection() { recoveryCandidate = nil; recoveryOriginal = nil; recoveryTarget = nil }
}

private struct StartupRecoveryInspection: Sendable {
    let candidate: LibrarySnapshot
    let original: Data?
}

#Preview("Native empty library · unverified on Windows") {
    EngramRootView(model: EngramModel(service: StudyService(repository: MemoryRepository(), scheduler: FSRSScheduler())))
}
