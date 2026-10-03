import SwiftUI
import Features
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import DesignSystem
import LearningCore
import AnkiAdapters
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@main
struct EngramApp: App {
    var body: some Scene {
        #if os(macOS)
        Window("Engram", id: "engram-library") {
            ApplicationRoot().frame(minWidth: 480, minHeight: 580)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .commands { CommandGroup(replacing: .newItem) { }; ScreenshotCommands() }
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
    @State private var screenshots = ScreenshotExportModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let model {
                Group {
                    if screenshots.touring, let copy = screenshots.copy {
                        ScreenshotTourView(export: screenshots, model: copy)
                    } else {
                        EngramRootView(model: model, portabilityAction: { portabilityPresented = true }, screenshotAction: { screenshots.prepare() })
                    }
                }
                .sheet(isPresented: $screenshots.presented) { ScreenshotExportView(export: screenshots, source: model) }
                #if os(macOS)
                .focusedSceneValue(\.screenshotAction, canCapture(model) ? { screenshots.prepare() } : nil)
                #endif
            }
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
        #if DEBUG
        .transformEnvironment(\.dynamicTypeSize) { size in
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-large-text") { size = .accessibility3 }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-largest-text") { size = .accessibility5 }
        }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { screenshots.cancel() }
            if phase == .active { model?.reminders.reconcile() }
        }
    }
    private func canCapture(_ model: EngramModel) -> Bool {
        model.loaded && !model.busy && !screenshots.running && !screenshots.presented &&
        !portabilityPresented && !model.editorPresented && !model.reviewPresented &&
        !model.settingsPresented && !model.creationPresented && model.notebookDeckID == nil && model.questionsDeckID == nil && model.activeContentDeckID == nil && model.deckForm == nil && model.deleteDeck == nil && model.deleteNote == nil
    }
    private func libraryLocation() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Engram", isDirectory: true).appendingPathComponent("library.json")
    }
    @MainActor private func openLibrary() async {
        failure = nil
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                let defaults = UserDefaults(suiteName: "engram.ui-tests")!
                defaults.removePersistentDomain(forName: "engram.ui-tests")
                if ProcessInfo.processInfo.arguments.contains("--ui-dark") { defaults.set("dark", forKey: "engram.appearance.v1") }
                if ProcessInfo.processInfo.arguments.contains("--ui-neutral") { defaults.set("neutral", forKey: "engram.theme.v1") }
                if ProcessInfo.processInfo.arguments.contains("--ui-monochrome") { defaults.set("monochrome", forKey: "engram.theme.v1") }
                let scheduler = FSRSScheduler(), now = Date()
                var snapshot = LibrarySnapshot()
                snapshot.decks = [Deck(id: "ui-deck", name: "AWS Cloud Practitioner")]
                if ProcessInfo.processInfo.arguments.contains("--ui-minimalist") {
                    snapshot.decks[0].notebookBlocks = [
                        NotebookBlock(id: "ui-cloud", text: "# Cloud fundamentals\nCloud computing provides on-demand access to computing resources. Instead of buying servers before you know how much capacity you need, provision resources when they are useful and release them when they are not.\n\nElasticity matches capacity to demand. Scalability describes the ability to grow. These ideas are related, but they describe different decisions. Pay-as-you-go pricing helps connect spending to actual usage."),
                        NotebookBlock(id: "ui-cloudfront", text: "# AWS CloudFront\nCloudFront is a content delivery network. It caches content at edge locations close to users, reducing latency and the number of requests reaching the origin. The origin can be an S3 bucket or a web server.\n\nAn edge location is not an Availability Zone. Edge locations deliver cached content; Availability Zones provide isolated infrastructure within a Region. Remember this distinction when choosing an answer about global content delivery."),
                        NotebookBlock(id: "ui-security", text: "# Shared responsibility\nAWS protects the infrastructure that runs its services. Customers protect their data and configure access to the services they use. The boundary changes with the service: managing an EC2 guest operating system is a customer responsibility, while an S3 customer configures access to stored objects.\n\nUse least privilege when granting permissions. IAM policies define allowed actions on resources. CloudTrail records account activity, helping you investigate who performed an action."),
                        NotebookBlock(id: "ui-cost", text: "# Cost and billing\nAWS Budgets helps you compare spending against a planned amount and configure alerts. Cost Explorer helps you investigate spending patterns over time. Pricing Calculator estimates costs before you deploy.\n\nChoose the service that matches the question: an estimate before deployment, an analysis of past spending, or an alert when costs cross a limit. These are different needs and should not be treated as interchangeable.")
                    ]
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-history-fixture") {
                    var conversation = LearningConversation(id:"today:ui-deck")
                    conversation.messages = [
                        LearningChatMessage(role:"user",text:"Explain AWS CloudFront"),
                        LearningChatMessage(role:"assistant",text:"CloudFront caches content near readers at edge locations.")
                    ]
                    var state = LearningAssistantState()
                    state.conversations = [conversation]
                    snapshot.assistantState = state
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-rich-theme-fixture") {
                    snapshot.decks[0].notebookBlocks = [NotebookBlock(id:"ui-rich",text:"# Theme rendering\nReadable **bold** and *italic* notes.\n\n> A quotation uses the shared theme.\n\n```swift\nlet recall = 0.9\n```\n\n$$R(t) = e^{-t/S}$$\n\n```mermaid\ngraph LR\n  Learn --> Review\n  Review --> Remember\n```")]
                }
                #if os(iOS)
                if ProcessInfo.processInfo.arguments.contains("--ui-image-fixture") {
                    let image = UIGraphicsImageRenderer(size:CGSize(width:600,height:400)).jpegData(withCompressionQuality:0.8) { _ in
                        UIColor(red:0.17,green:0.27,blue:0.18,alpha:1).setFill()
                        UIBezierPath(rect:CGRect(x:0,y:0,width:600,height:400)).fill()
                        ("CloudFront\nedge locations" as NSString).draw(in:CGRect(x:50,y:120,width:500,height:160),
                            withAttributes:[.font:UIFont.systemFont(ofSize:42,weight:.medium),.foregroundColor:UIColor.white])
                    }
                    snapshot.decks[0].documents = [LibraryDocument(id:"9E2B947C-DBFC-4DF4-A15E-921021983344",
                        name:"CloudFront diagram.jpg",kind:.image,
                        pages:[PDFPageText(number:1,text:"CloudFront edge locations cache content near users.")],originalData:image)]
                }
                #endif
                let studyQuestions = [
                    ("Which service delivers cached content close to users? A) Amazon EC2 B) Amazon CloudFront C) AWS CloudTrail D) Amazon RDS", "B) Amazon CloudFront. It caches content at edge locations, reducing latency and origin load."),
                    ("What is cloud computing?", "On-demand access to computing resources."),
                    ("Who manages the guest operating system on Amazon EC2? A) AWS B) The customer C) The internet provider D) The hardware manufacturer", "B) The customer. AWS manages the underlying infrastructure; customers patch and secure the guest operating system."),
                    ("What is the difference between elasticity and scalability?", "Elasticity adjusts capacity to current demand. Scalability is the ability to handle increasing demand by adding capacity."),
                    ("Which tool can alert you when spending exceeds a planned amount? A) AWS Budgets B) Amazon Route 53 C) AWS CloudTrail D) Amazon CloudFront", "A) AWS Budgets. Configure cost or usage budgets and alerts to track spending against your plan.")
                ]
                for index in 0..<5 {
                    let id = "ui-card-\(index)"
                    let question = ProcessInfo.processInfo.arguments.contains("--ui-minimalist") ? studyQuestions[index] : ("What is cloud computing?", "On-demand access to computing resources.")
                    snapshot.notes.append(Note(id: id, deckID: "ui-deck", kind: .basic, front: question.0, back: question.1))
                    var state = try scheduler.initialState(now: now, settings: snapshot.settings)
                    if ProcessInfo.processInfo.arguments.contains("--ui-minimalist") && index < 4 {
                        state = try scheduler.importState(due: now.addingTimeInterval(Double(index - 1) * 86400), phase: .review,
                            sourceValues: ["s": String(3 + index * 2), "d": "5", "lrt": String(now.addingTimeInterval(-Double(index + 1) * 86400).timeIntervalSince1970), "ivl": "5", "reps": "3", "lapses": "0"], settings: snapshot.settings)
                    }
                    snapshot.cards.append(StudyCard(id: id, noteID: id, deckID: "ui-deck", schedule: state))
                    for day in 0..<7 where (index + day) % 3 != 0 {
                        let time = now.addingTimeInterval(-Double(day) * 86400 - 60)
                        snapshot.reviews.append(ReviewEvent(id: "ui-review-\(index)-\(day)", cardID: id, deckID: "ui-deck", sessionID: "ui-session", rating: .good, reviewedAt: time, committedAt: time, before: state, after: state))
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-review-mcq-fixture") {
                    snapshot.notes = Array(snapshot.notes.prefix(1))
                    snapshot.cards = Array(snapshot.cards.prefix(1))
                    snapshot.reviews = snapshot.reviews.filter { $0.cardID == "ui-card-0" }
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--ui-long-mcq") || arguments.contains("--ui-two-choices") || arguments.contains("--ui-eight-choices") {
                        let count = arguments.contains("--ui-two-choices") ? 2 : arguments.contains("--ui-eight-choices") ? 8 : 4
                        let long = arguments.contains("--ui-long-mcq")
                        let prompt = long ? "A research team publishes reports worldwide from an Amazon S3 origin. Readers in several countries experience slow page loads, especially when opening reports containing detailed images. The team wants to reduce delivery latency and repeated requests to the origin without changing its application, database, or access policies. Cached content must be delivered from locations near readers. Which approach best meets these requirements? Consider content delivery separately from compute capacity, auditing, and long-term archival storage." : "Which service delivers cached content close to users?"
                        let options = (0..<count).map { index -> String in
                            let letter = String(UnicodeScalar(65 + index)!)
                            let text = index == 1 ? "Amazon CloudFront" : index == 7 ? "AverylongunbrokentermusedtotestwrappingwithoutclippingΩ_日本語_é" : "Alternative service \(index + 1)"
                            let detail = !long ? "" : index == 1 ? " caches frequently requested reports and images at edge locations near readers, while retaining the existing S3 origin and application." : " handles a different workload. Infrastructure, archival storage, and auditing do not by themselves deliver cached website content from edge locations."
                            return letter + ") " + text + detail
                        }.joined(separator: "\n")
                        let explanation = "B) Amazon CloudFront. CloudFront delivers cached objects from edge locations close to readers, reducing round trips to the origin. The S3 bucket remains the origin. Compute scaling and audit logging solve different problems.\n\nThis explanation deliberately spans multiple lines to exercise scrolling and wrapping; it should remain attached to the correct answer after rotation."
                        snapshot.notes[0] = Note(id:"ui-card-0",deckID:"ui-deck",kind:.basic,front:prompt + "\n" + options,back:explanation)
                    }
                }
                model = EngramModel(service: StudyService(repository: MemoryRepository(initial: snapshot), scheduler: scheduler), defaults: defaults)
                return
            }
            #endif
            let location = try libraryLocation()
            let repository = try await Task.detached(priority: .userInitiated) { try SQLiteLibraryRepository(url: location.deletingLastPathComponent().appendingPathComponent("library.sqlite"), migrating: location) }.value
            let opened = EngramModel(service: StudyService(repository: repository, scheduler: FSRSScheduler()), repository: repository)
            model = opened
            opened.reminders.reconcile()
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
            let dataDirectory = target.deletingLastPathComponent()
            let sqlite = dataDirectory.appendingPathComponent("library.sqlite")
            if FileManager.default.fileExists(atPath:sqlite.path) {
                let archive = dataDirectory.appendingPathComponent("Recovery originals",isDirectory:true).appendingPathComponent(UUID().uuidString,isDirectory:true)
                try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
                let files = [sqlite,URL(fileURLWithPath:sqlite.path + "-wal"),URL(fileURLWithPath:sqlite.path + "-shm")].filter { FileManager.default.fileExists(atPath:$0.path) }
                for file in files {
                    let copy = archive.appendingPathComponent(file.lastPathComponent)
                    try FileManager.default.copyItem(at:file,to:copy)
                    guard try Data(contentsOf:file) == Data(contentsOf:copy) else { throw EngramError.storage("Database recovery archive verification failed.") }
                }
                for file in files { try FileManager.default.removeItem(at:file) }
            }
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

#if os(iOS)
#Preview("Library · populated · preview data only") {
    LibraryLandingPreview()
}

private struct LibraryLandingPreview: View {
    private static let defaults = UserDefaults(suiteName: "engram.preview.library")!
    @State private var model: EngramModel = {
        var snapshot = LibrarySnapshot()
        let now = Date()
        let names = ["AWS::Cloud Concepts", "AWS::Security", "AWS::Storage", "Biology", "Spanish", "Reading notes"]
        for (index, name) in names.enumerated() {
            let id = "preview-deck-\(index)"
            snapshot.decks.append(Deck(id: id, name: name))
            guard index < 5 else { continue }
            for card in 0..<(index + 2) {
                let noteID = "\(id)-\(card)"
                snapshot.notes.append(Note(id: noteID, deckID: id, kind: .basic, front: "Preview question \(card + 1)", back: "Preview answer"))
                snapshot.cards.append(StudyCard(id: noteID, noteID: noteID, deckID: id, ordinal: 0,
                    schedule: ScheduleState(schedulerID: "preview", implementationVersion: "1",
                        due: now.addingTimeInterval(index < 2 ? -600 : 86_400), phase: index == 2 ? .new : .review)))
            }
        }
        let model = EngramModel(service: StudyService(repository: MemoryRepository(initial: snapshot), scheduler: FSRSScheduler()), defaults: defaults)
        model.destination = .library
        return model
    }()
    var body: some View { EngramRootView(model: model).defaultAppStorage(Self.defaults) }
}
#endif
