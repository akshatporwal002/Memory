import SwiftUI
import LearningCore
import DesignSystem

/// A writing page, not a sequence of card-entry sheets.
struct LibraryCreateDeckView: View {
    @Bindable var model: EngramModel
    let created: (String) -> Void
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focus: Field?
    @State private var discard = false
    @State private var showHelp = false
    @State private var showFolder = false
    @State private var parsed = DeckDocument.parse("")
    @State private var showPDF = false
    @State private var pdfCreatedDeckID: String?
    private enum Field { case title, subject, document }
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var subjects: [String] {
        let paths = model.library.liveDecks.flatMap { deck -> [String] in
            let pieces = deck.name.components(separatedBy: "::")
            return (1..<pieces.count).map { pieces.prefix($0).joined(separator: "::") }
        }
        return Array(Set(paths)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var canCreate: Bool {
        !model.busy && parsed.issues.isEmpty &&
        !model.deckCreationDraft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Untitled deck", text: $model.deckCreationDraft.title, axis: .vertical)
                    .textFieldStyle(.plain).font(theme.font(.title)).focused($focus, equals: .title)
                    .accessibilityLabel("Deck title").accessibilityIdentifier("deck-title")
                if showFolder || !model.deckCreationDraft.subject.isEmpty { subjectField }
                Button(model.pdfLearning.draft.source == nil ? "Learn from a PDF" : "Resume PDF learning", systemImage: "doc.text") {
                    focus = nil; pdfCreatedDeckID = nil; showPDF = true
                }.accessibilityIdentifier("deck-pdf-learning")
                HStack(alignment: .firstTextBaseline) {
                    Text("Question: answer")
                        .font(.subheadline).foregroundStyle(palette.secondaryText)
                    Spacer(minLength: 0)
                    if !parsed.questions.isEmpty {
                        Text("\(parsed.questions.count) cards").font(.subheadline).foregroundStyle(palette.secondaryText).monospacedDigit()
                    }
                }
                if showHelp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("One line, one card").font(.headline)
                        Text("Use a colon and a space between the question and answer. Each line makes one card. Existing -> and → lines still work.")
                        Text("Use # for headings. Start a line with a backslash (\\) to keep text such as Note: remember this as ordinary writing.")
                    }.font(.subheadline).foregroundStyle(palette.secondaryText)
                }
                ZStack(alignment: .topLeading) {
                    if model.deckCreationDraft.document.isEmpty {
                        Text("Write your notes here…\n\nWhat is cloud computing?: Computing resources on demand.")
                            .foregroundStyle(palette.secondaryText)
                            .padding(.top, 8).padding(.horizontal, 5).allowsHitTesting(false).accessibilityHidden(true)
                    }
                    TextEditor(text: $model.deckCreationDraft.document)
                        .scrollContentBackground(.hidden).frame(minHeight: 300)
                        .focused($focus, equals: .document)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Deck document").accessibilityIdentifier("deck-document")
                }.font(.body).lineSpacing(4)
                if !parsed.issues.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(parsed.issues.prefix(5)) { issue in
                            Text(issue.line > 0 ? "Line \(issue.line): \(issue.message)" : issue.message)
                        }
                        if parsed.issues.count > 5 { Text("And \(parsed.issues.count - 5) more incomplete lines.") }
                    }.font(.subheadline).foregroundStyle(palette.accentInk).accessibilityIdentifier("deck-document-issues")
                }
                if let error = model.error { EngramInlineError(message: error) }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
                .disabled(model.busy)
        }
        .scrollDismissesKeyboard(.interactively)
        .engramCanvas().navigationTitle("New notebook").engramInlineTitle().engramHideStudyTabs()
        .engramHideBack(model.busy)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              if !showPDF {
                Button("Create", action: create).fontWeight(.semibold).disabled(!canCreate)
                    .accessibilityIdentifier("deck-create")
              }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(showFolder ? "Hide folder" : "Choose folder", systemImage: "folder") { showFolder.toggle() }
                    Button(showHelp ? "Hide writing help" : "Writing help", systemImage: "questionmark.circle") { showHelp.toggle() }
                    Button("Load AWS sample", systemImage: "book") { loadSample() }
                        .disabled(!model.deckCreationDraft.isEmpty || model.busy)
                    Divider()
                    Button("Discard draft", role: .destructive) { discard = true }.disabled(model.deckCreationDraft.isEmpty || model.busy)
                } label: { Label("Notebook options", systemImage: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Discard this draft?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) {
                model.deckCreationDraft = DeckCreationDraft(); model.error = nil; focus = .title
            }
        } message: { Text("This removes the unfinished title and document. Your existing decks are unchanged.") }
        .onAppear {
            model.error = nil
            parsed = DeckDocument.parse(model.deckCreationDraft.document)
            focus = model.deckCreationDraft.title.isEmpty ? .title : .document
        }
        .onChange(of: model.deckCreationDraft.document) { _, value in parsed = DeckDocument.parse(value) }
        .navigationDestination(isPresented: $showPDF) {
            if let id = pdfCreatedDeckID { DeckOverviewView(model: model, deckID: id) }
            else { PDFLearningView(model: model) { id in model.selectedDeckID = id; pdfCreatedDeckID = id } }
        }
    }

    private var subjectField: some View {
        HStack(spacing: 10) {
            Text("Subject").font(.subheadline).foregroundStyle(palette.secondaryText)
            TextField("Unfiled · optional", text: $model.deckCreationDraft.subject)
                .textFieldStyle(.plain).font(.subheadline).focused($focus, equals: .subject)
                .accessibilityLabel("Subject or folder path").accessibilityIdentifier("deck-subject")
            if !subjects.isEmpty {
                Menu {
                    Button("Unfiled") { model.deckCreationDraft.subject = "" }
                    ForEach(subjects, id: \.self) { subject in
                        Button(subject.replacingOccurrences(of: "::", with: " / ")) { model.deckCreationDraft.subject = subject }
                    }
                } label: { Image(systemName: "chevron.up.chevron.down").frame(width: 44, height: 44) }
                    .accessibilityLabel("Choose existing subject")
            }
        }.frame(minHeight: 44)
    }

    private func loadSample() {
        guard model.deckCreationDraft.isEmpty else { return }
        guard let url = Bundle.module.url(forResource: "AWS-Cloud-Practitioner-Sample", withExtension: "txt"),
              let document = try? String(contentsOf: url, encoding: .utf8) else {
            model.error = "The sample could not be opened."; return
        }
        model.deckCreationDraft = DeckCreationDraft(title: "AWS Cloud Practitioner · Practice", document: document)
        focus = nil
    }

    private func create() {
        guard canCreate else { return }
        let draft = model.deckCreationDraft
        focus = nil
        Task {
            var id: String?
            if await model.perform({ id = try await $0.createDeck(from: draft).id }), let id {
                model.deckCreationDraft = DeckCreationDraft()
                created(id)
            }
        }
    }
}
