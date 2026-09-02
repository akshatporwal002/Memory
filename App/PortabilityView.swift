import SwiftUI
import UniformTypeIdentifiers
import Observation
import Features
import LearningCore
import StudyApplication
import SchedulingAdapters
import AnkiAdapters
import DesignSystem

extension UTType {
    static let engramBackup = UTType(exportedAs: "dev.engram.study.backup", conformingTo: .zip)
    static let ankiDeck = UTType(importedAs: "net.anki.apkg", conformingTo: .zip)
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .engramBackup, .ankiDeck] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw EngramError.invalid("The selected file is not readable.") }
        bytes = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

@MainActor @Observable final class PortabilityModel {
    let model: EngramModel
    let backupDirectory: URL
    var busy = false
    var message: String?
    var error: String?
    var inspection: AnkiInspection?
    var sourceIdentity = UserDefaults.standard.string(forKey: "engram.importSource.v1") ?? ""
    var restored: LibrarySnapshot?
    var inspectedRevision = 0
    var scheduling = "choose"
    var duplicates: DuplicateImportPolicy = .keepExisting
    var destination = ""
    var replacement = false
    var exportScope = ""
    var exportMode = "personal"
    var exportDocument: ExportDocument?
    var exportName = "Engram.engram"
    var showExporter = false
    var recentBackups: [URL] = []

    init(model: EngramModel, backupDirectory: URL) { self.model = model; self.backupDirectory = backupDirectory; reloadBackups() }
    func reloadBackups() {
        recentBackups = ((try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "engram" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func inspect(_ url: URL) async {
        guard !busy else { return }; busy = true; error = nil; message = nil; inspection = nil; restored = nil
        defer { busy = false }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let original = try await model.service.snapshot(); inspectedRevision = original.revision
            if url.pathExtension.lowercased() == "engram" {
                restored = try await Task.detached(priority: .userInitiated) { try NativeBackupAdapter.read(from: url) }.value
            } else {
                let label = sourceIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
                let namespace: String? = label.isEmpty ? nil : "user-source:" + label
                UserDefaults.standard.set(label, forKey: "engram.importSource.v1")
                inspection = try await Task.detached(priority: .userInitiated) { try AnkiPackageAdapter.inspect(url: url, namespace: namespace) }.value
            }
            scheduling = "choose"; replacement = false
        } catch { self.error = error.localizedDescription }
    }
    func confirmImport() async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false; reloadBackups() }
        do {
            let candidate: LibrarySnapshot
            if let restored { candidate = restored }
            else if let inspection {
                guard inspection.sourceLibraryID != model.library.libraryID else {
                    throw EngramError.invalid("This package came from this Engram library. Use a complete Engram backup to restore it; importing its Anki export back here could duplicate cards and review evidence.")
                }
                guard scheduling == "preserve" || scheduling == "content" else { throw EngramError.invalid("Choose how to treat the imported study progress.") }
                let settings = model.library.settings
                let treatment: AnkiSchedulingTreatment = scheduling == "preserve" ? .preserveSource : .contentOnly
                candidate = try await Task.detached(priority: .userInitiated) {
                    try inspection.makeLibrary(scheduling: treatment, scheduler: FSRSScheduler(), now: Date(), settings: settings)
                }.value
            } else { return }
            let backupURL = try nextBackupURL()
            let backup: @Sendable (LibrarySnapshot) async throws -> Void = { snapshot in
                try await Task.detached(priority: .userInitiated) { try NativeBackupAdapter.write(snapshot, to: backupURL) }.value
            }
            let revision = inspectedRevision
            let success: Bool
            var summary: ImportSummary?
            if restored != nil || replacement {
                success = await model.perform { try await $0.replaceLibrary(candidate, expectedRevision: revision, preImportBackup: backup) }
            } else {
                let policy = duplicates, destinationID: String? = destination.isEmpty ? nil : destination
                success = await model.perform { summary = try await $0.mergeImport(candidate, duplicates: policy, destinationDeckID: destinationID, expectedRevision: revision, preImportBackup: backup) }
            }
            if success {
                if let summary {
                    message = "Import saved: \(summary.addedNotes) notes added, \(summary.updatedNotes) updated, \(summary.skippedNotes) kept or skipped; \(summary.addedCards) cards, \(summary.addedHistory) history records and \(summary.addedMedia) media files added. Your previous library is available under Recovery backups below."
                } else {
                    message = "Library restored: \(candidate.liveNotes.count) notes, \(candidate.liveCards.count) cards and \(candidate.media.count) media files. Your previous library is available under Recovery backups below."
                }
                inspection = nil; restored = nil
            } else { error = model.error }
        } catch { self.error = error.localizedDescription }
    }
    func prepareExport(native: Bool) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false }
        do {
            let snapshot = try await model.service.snapshot()
            let deckIDs: Set<String>? = exportScope.isEmpty ? nil : Set([exportScope])
            let mode: AnkiExportMode = exportMode == "personal" ? .personalTransfer : .sharing
            let data = try await Task.detached(priority: .userInitiated) {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let output = directory.appendingPathComponent(native ? "Engram.engram" : "Engram.apkg")
                if native { try NativeBackupAdapter.write(snapshot, to: output) }
                else { try AnkiPackageAdapter.export(snapshot: snapshot, deckIDs: deckIDs, mode: mode, to: output) }
                return try Data(contentsOf: output)
            }.value
            exportName = native ? "Engram.engram" : "Engram.apkg"
            exportDocument = ExportDocument(bytes: data); showExporter = true
        } catch { self.error = error.localizedDescription }
    }
    private func nextBackupURL() throws -> URL {
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return backupDirectory.appendingPathComponent("Before-import-\(stamp)-\(UUID().uuidString.prefix(6)).engram")
    }
}

struct PortabilityView: View {
    @Bindable var transfer: PortabilityModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @State private var choosingFile = false
    @State private var confirmReplacement = false
    var body: some View {
        NavigationStack {
            Form {
                if transfer.busy { Section { ProgressView("Processing your library…"); Text("Large packages can take a moment. Changes are saved only after validation and backup.") } }
                if let error = transfer.error { Section { EngramInlineError(message: error) } }
                if let message = transfer.message { Section { Label(message, systemImage: "checkmark.circle") } }
                Section("Bring your cards") {
                    TextField("Anki source name (optional)", text: $transfer.sourceIdentity)
                        .onChange(of: transfer.sourceIdentity) { _, _ in transfer.inspection = nil }
                    Text("Use a distinct name for each Anki profile, and reuse that name for later exports from the same profile. Leave blank to identify an external package by its exact file contents; a changed export will then be treated as a separate source. Engram exports carry their own stable library identity.")
                        .font(theme.font(.metadata))
                    Button("Choose Anki package or Engram backup") { choosingFile = true }
                    Text("Import .apkg or .colpkg exported with Anki’s ‘Support older Anki versions’ option, or restore a complete .engram backup. Files remain on this device.")
                        .font(theme.font(.metadata))
                }
                if let inspection = transfer.inspection { importReport(inspection) }
                if let restored = transfer.restored {
                    Section("Restore complete library") {
                        Text("\(restored.liveDecks.count) decks · \(restored.liveCards.count) cards · \(restored.media.count) media files · \(restored.reviews.count + restored.importedReviews.count) review records")
                        Text("Restoring replaces this device’s active library. A complete recovery backup is written first.")
                        Button("Restore this backup…", role: .destructive) { confirmReplacement = true }
                        Button("Cancel restore", role: .cancel) { transfer.restored = nil }
                    }
                }
                Section("Export to Anki") {
                    Picker("Decks", selection: $transfer.exportScope) {
                        Text("Entire supported library").tag("")
                        ForEach(transfer.model.library.liveDecks) { Text($0.name).tag($0.id) }
                    }
                    Picker("Export mode", selection: $transfer.exportMode) {
                        Text("Personal transfer — include study progress").tag("personal")
                        Text("Sharing — content without personal progress").tag("sharing")
                    }
                    Text("Referenced media and all sibling cards of selected notes are included. Personal transfer preserves supported scheduling and history; export reports unmappable states. Native backup retains everything, including source originals and undo evidence.")
                        .font(theme.font(.metadata))
                    Button("Export Anki package") { Task { await transfer.prepareExport(native: false) } }
                }
                Section("Complete backup") {
                    Text("Save your entire library, media, original imported fields, schedules and review evidence. Keep a copy outside the app: deleting the app or losing the device can remove local data.")
                    Button("Save complete Engram backup") { Task { await transfer.prepareExport(native: true) } }
                }
                if !transfer.recentBackups.isEmpty {
                    Section("Recovery backups") {
                        ForEach(transfer.recentBackups, id: \.self) { url in
                            Button(url.deletingPathExtension().lastPathComponent) { Task { await transfer.inspect(url) } }
                        }
                    }
                }
            }
            .disabled(transfer.busy).navigationTitle("Import and export")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(transfer.busy) } }
            .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { Task { await transfer.inspect(url) } }
                case .failure(let error): transfer.error = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $transfer.showExporter, document: transfer.exportDocument, contentType: transfer.exportName.hasSuffix(".engram") ? .engramBackup : .ankiDeck, defaultFilename: transfer.exportName) { result in
                switch result {
                case .success: transfer.message = "Export saved. Keep it somewhere safe."
                case .failure(let error): transfer.error = error.localizedDescription
                }
            }
            .confirmationDialog("Replace this device’s library?", isPresented: $confirmReplacement, titleVisibility: .visible) {
                Button("Back up current library and replace", role: .destructive) { Task { await transfer.confirmImport() } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("The imported library will become active. The previous library is saved first as a recovery backup; cancelling changes nothing.") }
            .engramCanvas()
        }
        .frame(idealWidth: 760).interactiveDismissDisabled(transfer.busy)
        .environment(\.engramTheme, transfer.model.theme).preferredColorScheme(transfer.model.appearance.colorScheme)
    }
    @ViewBuilder private func importReport(_ inspection: AnkiInspection) -> some View {
        Section("Package inspection") {
            let report = inspection.report
            Text("\(report.deckCount) decks · \(report.noteCount) notes · \(report.cardCount) cards")
            Text("\(report.mediaCount) media files · \(report.historyCount) source review records")
            ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                Label(finding.message, systemImage: finding.severity == .blocking ? "xmark.octagon" : "info.circle")
                    .font(theme.font(.metadata))
            }
            if inspection.sourceLibraryID == transfer.model.library.libraryID {
                Text("This package originated from this Engram library. To recover this library, choose a complete .engram backup and Restore. Anki transfer back into the same library is blocked to prevent duplicate cards or history.")
            } else if report.canImport {
                Picker("Study progress", selection: $transfer.scheduling) {
                    Text("Choose a treatment").tag("choose")
                    if report.canContinueScheduling { Text("Preserve supported due dates and FSRS memory").tag("preserve") }
                    Text("Content only — restart cards as new").tag("content")
                }
                if transfer.scheduling == "content" { Text("Cards will start again as new. Original scheduling and source review history remain retained as evidence for backup/export.").foregroundStyle(.secondary) }
                Toggle("Replace active library after backup", isOn: $transfer.replacement)
                if !transfer.replacement {
                    Picker("Destination", selection: $transfer.destination) {
                        Text("Preserve imported deck hierarchy").tag("")
                        ForEach(transfer.model.library.liveDecks) { Text("Move all imported cards to " + $0.name).tag($0.id) }
                    }
                    Picker("Repeated notes", selection: $transfer.duplicates) {
                        ForEach(DuplicateImportPolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Button(transfer.replacement ? "Review replacement…" : "Back up and import") {
                    if transfer.replacement { confirmReplacement = true } else { Task { await transfer.confirmImport() } }
                }.disabled(transfer.scheduling == "choose")
            }
            Button("Cancel this import", role: .cancel) { transfer.inspection = nil }
        }
    }
}
