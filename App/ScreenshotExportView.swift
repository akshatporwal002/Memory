import SwiftUI
import UniformTypeIdentifiers
import Features
import DesignSystem
import LearningCore

struct ScreenshotZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var bytes: Data
    init(bytes: Data) { self.bytes = bytes }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw EngramError.invalid("Could not read the screenshot ZIP.") }
        self.bytes = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
}

struct ScreenshotExportView: View {
    @Bindable var export: ScreenshotExportModel
    let source: EngramModel
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(iOS)
                    Label("A full UI tour, saved to Photos", systemImage: "photo.on.rectangle")
                        .font(.title2)
                    #else
                    Label("A full UI tour, in one ZIP", systemImage: "camera.on.rectangle")
                        .font(.title2)
                    #endif
                    Text("Capture Today, Library, Activity, Settings, import/export, deck forms, available card editors and review screens. Long pages get overlapping screenshots.")
                    Text("This uses your current theme and an isolated copy of your library. It does not save edits or grades, or capture other apps. It returns to your selected screen; scroll positions may reset.")
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    Label("Screenshots can include private card text, deck names and images. Engram only asks to add photos, not read your library. Photos may sync them through iCloud if enabled. Review them before sharing.", systemImage: "hand.raised")
                        .font(.callout)
                    #else
                    Label("Screenshots can include private card text, deck names and images. Review the ZIP before sharing it. Nothing is uploaded automatically.", systemImage: "hand.raised")
                        .font(.callout)
                    #endif
                    Text("Keep Engram in the foreground while it captures. Empty libraries skip screens requiring cards. Capture notes list skipped or truncated pages; this does not capture every card, popup or error state.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let error = export.error { EngramInlineError(message: error) }
                    if export.imageCount > 0 {
                        Label("\(export.imageCount) screenshots ready", systemImage: "checkmark.circle")
                        #if os(iOS)
                        if export.savedToPhotos {
                            Label("Saved \(export.imageCount) screenshots to Photos", systemImage: "checkmark.circle.fill")
                            Text("Open Photos to select and share the images.").foregroundStyle(.secondary)
                        } else {
                            Button("Save to Photos") { saving = true }
                                .buttonStyle(EngramButtonStyle())
                                .disabled(saving || export.savingPhotos)
                                .accessibilityIdentifier("save-screenshots-to-photos")
                            if saving || export.savingPhotos { ProgressView("Saving to Photos…") }
                        }
                        #else
                        Button("Save screenshot ZIP…") { saving = true }
                            .buttonStyle(EngramButtonStyle())
                        if saved { Text("Saved. You can attach the ZIP here, or unzip it and choose individual PNGs.").foregroundStyle(.secondary) }
                        #endif
                        DisclosureGroup("Capture notes") {
                            ForEach(export.captureNotes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    } else {
                        Button("Capture all pages") { export.start(source: source) }
                            .buttonStyle(EngramButtonStyle())
                            .accessibilityIdentifier("capture-all-pages")
                    }
                }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }
            .navigationTitle("Screenshots")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(saving) } }
            .engramCanvas()
        }
        .frame(idealWidth: 660, idealHeight: 640)
        #if os(iOS)
        .interactiveDismissDisabled(saving || export.savingPhotos)
        .task(id: saving) {
            guard saving else { return }
            await export.saveToPhotos()
            saving = false
        }
        #else
        .fileExporter(isPresented: $saving, document: export.document, contentType: .zip, defaultFilename: export.filename) { result in
            switch result {
            case .success: saved = true
            case .failure(let error): export.error = "Could not save the ZIP. You can retry. \(error.localizedDescription)"
            }
        }
        #endif
        .environment(\.engramTheme, source.theme)
        .preferredColorScheme(source.appearance.colorScheme)
    }
}

struct ScreenshotTourView: View {
    @Bindable var export: ScreenshotExportModel
    let model: EngramModel
    var body: some View {
        EngramRootView(model: model, portabilityAction: { }, screenshotAction: { }, capturingScreenshots: true)
            .background(alignment: .topLeading) {
                ScreenshotWindowProbe(capture: export.capture).frame(width: 0, height: 0)
            }
            .sheet(isPresented: $export.portabilityPresented) {
                if let transfer = export.transfer { PortabilityView(transfer: transfer).engramCaptureSurface() }
            }
            .environment(\.engramScreenshotCapture, true)
            .environment(\.engramScreenshotEditorPreview, export.editorPreview)
            .environment(\.engramScreenshotAcknowledgements, export.acknowledgements)
            .environment(\.engramScreenshotProgress, export.progress)
            .environment(\.engramScreenshotHideControls, export.hidingProgress)
            .environment(\.engramScreenshotCancel, { export.cancel() })
    }
}

#if os(macOS)
private struct ScreenshotActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var screenshotAction: (() -> Void)? {
        get { self[ScreenshotActionKey.self] }
        set { self[ScreenshotActionKey.self] = newValue }
    }
}
struct ScreenshotCommands: Commands {
    @FocusedValue(\.screenshotAction) private var action
    var body: some Commands {
        CommandMenu("Screenshots") {
            Button("Screenshot all pages…") { action?() }
                .keyboardShortcut("s", modifiers: [.command, .shift, .option])
                .disabled(action == nil)
        }
    }
}
#endif
