import SwiftUI
import UniformTypeIdentifiers
import LearningCore
import DesignSystem

struct PDFLearningView: View {
    @Bindable var model: EngramModel
    @Bindable var flow: PDFLearningController
    let created: (String) -> Void
    @State private var importer = false
    @State private var inspectSource = false
    @State private var discard = false
    @State private var loadedFixture = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    init(model: EngramModel, created: @escaping (String) -> Void) {
        self.model = model; self.flow = model.pdfLearning; self.created = created
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let source = flow.draft.source {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(source.filename).font(theme.font(.title))
                        Text("\(source.pages.count) pages · source text kept on this device").font(.subheadline).foregroundStyle(palette.secondaryText)
                        Button("Inspect source pages") { inspectSource = true }
                            .accessibilityIdentifier("pdf-source-inspect")
                        ForEach(source.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(palette.againInk) }
                    }
                    if flow.draft.sample.isEmpty && !flow.draft.approved { briefForm }
                    else if !flow.draft.approved { sampleReview }
                    else { fullReview }
                } else {
                    Text("Learn from a PDF").font(theme.font(.hero))
                    Text("Turn your reading into questions and clear learning notes, with references back to the source.")
                        .foregroundStyle(palette.secondaryText)
                    Button("Choose PDF", systemImage: "doc.badge.plus") { importer = true }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("pdf-choose")
                    Text("Readable PDFs · up to 25 MB and 300 pages. Scanned pages and diagrams require a text-searchable version.")
                        .font(.caption).foregroundStyle(palette.secondaryText)
                }
                if flow.busy {
                    HStack { ProgressView(); Text(flow.status).font(.subheadline) }
                    Button("Pause", action: flow.cancel).accessibilityIdentifier("pdf-pause")
                } else if !flow.status.isEmpty { Text(flow.status).font(.caption).foregroundStyle(palette.secondaryText) }
                ForEach(flow.notices, id: \.self) { Text($0).font(.caption).foregroundStyle(palette.secondaryText) }
                if let error = flow.error { EngramInlineError(message: error) }
                if let error = model.error { EngramInlineError(message: error) }
            }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("PDF learning").engramInlineTitle().engramCanvas().engramHideStudyTabs()
        .engramAssistantClearance()
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button("Inspect source pages") { inspectSource = true }.disabled(flow.draft.source == nil)
                    Button("Discard PDF draft", role: .destructive) { discard = true }
                } label: { Image(systemName: "ellipsis") }
                .disabled(flow.busy || model.busy)
            }
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf]) { result in
            switch result { case .success(let url): flow.load(url); case .failure(let error): flow.error = error.localizedDescription }
        }
        .sheet(isPresented: $inspectSource) {
            if let source = flow.draft.source { PDFSourcePagesView(source: source) }
        }
        .confirmationDialog("Discard the unfinished PDF learning draft?", isPresented: $discard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { flow.reset() }
        } message: { Text("Your saved decks and manual notebook draft are kept.") }
        .onDisappear { flow.cancel(); model.pdfLearningPresented = false }
        .onAppear {
            model.pdfLearningPresented = true
            #if DEBUG
            if !loadedFixture, ProcessInfo.processInfo.arguments.contains("--ui-testing"), ProcessInfo.processInfo.arguments.contains("--ui-pdf-fixture") { loadedFixture = true; flow.reset(); flow.loadFixture() }
            #endif
        }
    }
    private var briefForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What would you like to learn?").font(theme.font(.section))
            field("Deck title", text: $flow.draft.title, prompt: "Name this learning deck")
            field("What are you preparing for?", text: $flow.draft.brief.goal, prompt: "An exam, work task, or a new subject")
            field("Which topics should we cover?", text: $flow.draft.brief.topics, prompt: "Leave blank to cover the selected pages")
            field("Anything to leave out?", text: $flow.draft.brief.exclusions, prompt: "Optional topics to exclude")
            if let source = flow.draft.source {
                Menu("Use a heading from the PDF") {
                    ForEach(suggestedTopics(source), id: \.self) { heading in
                        Button(heading) { flow.draft.brief.topics = heading }
                    }
                }
                HStack {
                    Stepper("From page \(flow.draft.brief.firstPage)", value: $flow.draft.brief.firstPage, in: 1...source.pages.count)
                    Stepper("To page \(flow.draft.brief.lastPage)", value: $flow.draft.brief.lastPage, in: 1...source.pages.count)
                }.font(.subheadline)
            }
            picker("Difficulty", value: $flow.draft.brief.difficulty, options: ["Beginner", "Intermediate", "Advanced"])
            picker("Create", value: $flow.draft.brief.output, options: ["Questions and notes", "Questions only", "Notes only"])
            if flow.draft.brief.output != "Notes only" {
                picker("Question style", value: $flow.draft.brief.format, options: ["Mixed", "Multiple choice", "Short answer"])
                Stepper("Up to \(flow.draft.brief.questionCount) questions", value: $flow.draft.brief.questionCount, in: 3...40)
            }
            if flow.draft.brief.output != "Questions only" {
                picker("Notes", value: $flow.draft.brief.noteDepth, options: ["Condensed", "Detailed"])
            }
            Text("First, review a small sample. The full scope needs \(flow.batches.count) batches, each with generation and evidence checks. Fewer questions may be returned when the source is insufficient. Selected passages are sent to your connected ChatGPT model.")
                .font(.caption).foregroundStyle(palette.secondaryText)
            Button("Preview a sample") { flow.generateSample(model: model) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("pdf-preview")
            if model.chatGPT.activeAccount == nil {
                Button("Connect ChatGPT") { model.settingsPresented = true }
            }
        }.disabled(flow.busy)
    }
    private var sampleReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Does this feel right?").font(theme.font(.section))
            Text("Check the wording, difficulty and supporting evidence before generating the selected pages.")
                .font(.subheadline).foregroundStyle(palette.secondaryText)
            Text("Approved sample items are kept in the final draft. Generation adds to them and filters repeated questions.")
                .font(.caption).foregroundStyle(palette.secondaryText)
            ForEach(flow.draft.sample) { item in itemPreview(item) }
            Button("Approve sample & generate") { flow.generateAll(model: model) }
                .buttonStyle(.borderedProminent).accessibilityIdentifier("pdf-approve")
            Button("Adjust learning brief") { flow.changeBrief() }.accessibilityIdentifier("pdf-adjust")
            Button("Regenerate sample") { flow.generateSample(model: model) }
        }.disabled(flow.busy)
    }
    private var fullReview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(flow.draft.finished ? "Your learning draft" : "Building your learning draft").font(theme.font(.section))
            let questionCount = flow.draft.items.filter { $0.kind != "note" }.count
            let notesCount = flow.draft.items.filter { $0.kind == "note" }.count
            Text("\(questionCount) questions · \(notesCount) note sections · \(flow.draft.completedBatches)/\(flow.batches.count) batches checked")
                .font(.subheadline).foregroundStyle(palette.secondaryText)
            Text("Source checks reduce unsupported claims; they do not guarantee accuracy. Read the evidence and remove anything you do not want to study.")
                .font(.caption).foregroundStyle(palette.secondaryText)
            ForEach(flow.draft.items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    itemPreview(item)
                    DisclosureGroup("Edit wording") {
                        TextField("Question or heading", text: editing(item.id, keyPath: \.prompt), axis: .vertical)
                            .textFieldStyle(.plain).font(.headline).padding(.vertical, 8)
                        TextField("Answer or notes", text: editing(item.id, keyPath: \.answer), axis: .vertical)
                            .textFieldStyle(.plain).padding(.vertical, 8)
                        Text("Your edits are marked as unverified. Source references stay available.").font(.caption).foregroundStyle(palette.secondaryText)
                    }
                    Button("Remove", role: .destructive) { flow.draft.items.removeAll { $0.id == item.id } }.font(.caption)
                }.disabled(flow.busy || model.busy)
                Divider()
            }
            if !flow.busy {
                if flow.draft.finished {
                    Button("Save learning deck", action: save).buttonStyle(.borderedProminent)
                        .disabled(flow.draft.items.isEmpty || model.busy).accessibilityIdentifier("pdf-save")
                    if questionCount < flow.draft.brief.questionCount && flow.draft.brief.output != "Notes only" {
                        Text("\(questionCount) supported questions were retained from the requested maximum of \(flow.draft.brief.questionCount). A limited question set does not test every fact in the PDF.")
                            .font(.caption).foregroundStyle(palette.secondaryText)
                    }
                } else {
                    Button("Resume generation") { flow.generateAll(model: model) }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("pdf-resume")
                }
                Button("Start again with a different brief") { flow.changeBrief() }.disabled(model.busy)
            }
        }
    }
    private func itemPreview(_ item: PDFLearningItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.kind == "note" ? "Learning notes" : item.kind == "mcq" ? "Multiple choice" : "Short answer")
                .font(.caption).foregroundStyle(palette.secondaryText)
            Text(item.prompt).font(.headline)
            ForEach(Array(item.options.enumerated()), id: \.offset) { index, option in
                Text("\(String(UnicodeScalar(65 + index)!))) \(option)").font(.subheadline).italic()
                    .foregroundStyle(index == item.correctIndex ? palette.easyInk : palette.secondaryText)
            }
            Text(item.answer).foregroundStyle(item.kind == "note" ? palette.primaryText : palette.easyInk)
            Text(item.userEdited == true ? "Edited by you · not rechecked" : "Checked against source passages")
                .font(.caption).foregroundStyle(palette.secondaryText)
            DisclosureGroup("Supporting evidence") {
                ForEach(Array(item.citations.enumerated()), id: \.offset) { _, citation in
                    if let source = flow.draft.source, let passage = source.chunks.first(where: { $0.id == citation.passageID }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(source.filename) · page \(passage.page)").font(.caption.weight(.medium))
                            Text(citation.quote).font(.caption).textSelection(.enabled)
                        }.padding(.vertical, 8)
                    }
                }
            }.font(.subheadline)
        }
    }
    private func editing(_ id: String, keyPath: WritableKeyPath<PDFLearningItem, String>) -> Binding<String> {
        Binding(get: { flow.draft.items.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" }, set: { value in
            guard let index = flow.draft.items.firstIndex(where: { $0.id == id }) else { return }
            flow.draft.items[index][keyPath: keyPath] = value
            flow.draft.items[index].userEdited = true; flow.draft.items[index].verified = false
        })
    }
    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(prompt, text: text, axis: .vertical).textFieldStyle(.plain)
                .padding(.vertical, 8).accessibilityLabel(title)
            Divider()
        }
    }
    private func picker(_ title: String, value: Binding<String>, options: [String]) -> some View {
        Picker(title, selection: value) { ForEach(options, id: \.self) { Text($0).tag($0) } }.pickerStyle(.menu)
    }
    private func suggestedTopics(_ source: PDFLearningSource) -> [String] {
        let headings = source.pages.flatMap { $0.text.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { (5...90).contains($0.count) && !$0.hasSuffix(".") }
        var seen = Set<String>()
        return Array(headings.filter { seen.insert($0).inserted }.prefix(12))
    }
    private func save() {
        guard let source = flow.draft.source, flow.draft.finished, !flow.busy else { return }
        let draft = flow.draft
        Task {
            var id: String?
            if await model.perform({ id = try await $0.createPDFDeck(id: draft.id, title: draft.title,
                record: PDFLearningRecord(source: source, brief: draft.brief, items: draft.items)).id }), let id {
                flow.reset(); created(id)
            }
        }
    }
}

struct PDFSourcePagesView: View {
    let source: PDFLearningSource
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(source.pages) { page in
                DisclosureGroup("Page \(page.number)") {
                    Text(page.text.isEmpty ? "No selectable text was extracted from this page." : page.text)
                        .font(.body).textSelection(.enabled)
                }
            }.navigationTitle(source.filename).engramInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
