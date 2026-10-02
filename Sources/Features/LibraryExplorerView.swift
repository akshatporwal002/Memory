#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import LearningCore
import StudyApplication
import DesignSystem

/// Compact file-tree presentation over the existing deck hierarchy.
struct LibraryExplorerView: View {
    @Bindable var model: EngramModel
    var importAction: (() -> Void)?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var expanded = Set<String>()
    @State private var openedDeck: String?
    @State private var openedDocument: LibraryDocument?
    @State private var importing = false
    @State private var importDeckID: String?
    @State private var deleteDocument: (deckID: String, document: LibraryDocument)?
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var summaries: [LibraryDeckSummary] {
        LibraryDeckSummary.sorted(LibraryDeckSummary.make(in:model.library,now:model.now),by:.alphabetical,query:query)
    }
    private var nodes: [LibraryFolder] { LibraryFolder.tree(summaries) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    addMenu
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("FILES").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(palette.secondaryText)
                    HStack(spacing: 9) {
                        Image(systemName:"magnifyingglass").foregroundStyle(palette.secondaryText)
                        TextField("Find a notebook or file",text:$query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    }.font(.subheadline).frame(minHeight:44)
                    Divider()
                }
                if model.library.liveDecks.isEmpty {
                    VStack(alignment:.leading,spacing:10) {
                        Image(systemName:"folder").font(.title2).foregroundStyle(palette.secondaryText)
                        Text("A place for what you learn").font(theme.font(.section))
                        Text("Create a notebook, then add questions, PDFs or Markdown sources.")
                            .font(.subheadline).foregroundStyle(palette.secondaryText)
                        Button("Create notebook",action:newNotebook).font(.subheadline.weight(.semibold)).frame(minHeight:44)
                    }.padding(.top,30)
                } else if nodes.isEmpty {
                    Text("No matching notebooks or files").foregroundStyle(palette.secondaryText).padding(.top,30)
                } else {
                    LazyVStack(alignment:.leading,spacing:0) {
                        ForEach(nodes) { node in
                            LibraryExplorerNode(node:node,depth:0,expanded:$expanded,searching:!query.isEmpty,
                                                openDeck:openDeck,openDocument:{ openedDocument = $0 },
                                                newNotebook:newNotebook,importFile:beginImport,
                                                removeFile:{ deckID,document in deleteDocument = (deckID,document) })
                        }
                    }
                }
                if let importAction {
                    Button("Import or export library",action:importAction)
                        .font(.caption).foregroundStyle(palette.secondaryText).frame(minHeight:44)
                }
            }
            .padding(.horizontal,20).padding(.top,8).padding(.bottom,28)
            .frame(maxWidth:760).frame(maxWidth:.infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh() }
        .navigationDestination(item:$openedDeck) { id in LibraryDeckDestination(model:model,deckID:id) }
        .sheet(item:$openedDocument) { document in LibraryDocumentReader(document:document) }
        .fileImporter(isPresented:$importing,
                      allowedContentTypes:[.pdf, UTType(filenameExtension:"md") ?? .plainText],
                      allowsMultipleSelection:true) { result in Task { await importFiles(result) } }
        .confirmationDialog("Remove source file?",isPresented:Binding(get:{ deleteDocument != nil },set:{ if !$0 { deleteDocument = nil } })) {
            if let target = deleteDocument {
                Button("Remove \(target.document.name)",role:.destructive) {
                    Task { _ = await model.perform { try await $0.removeDocument(id:target.document.id,from:target.deckID) }; deleteDocument = nil }
                }
            }
            Button("Cancel",role:.cancel) { deleteDocument = nil }
        } message: { Text("Questions and review history stay in the notebook. The file and its retrieval passages will be removed.") }
        .onAppear {
            if expanded.isEmpty,let first = nodes.first { expanded.insert(first.path) }
            if let id = model.libraryDeckRequest { openDeck(id); model.libraryDeckRequest = nil }
        }
        .onChange(of:model.libraryDeckRequest) { _,id in if let id { openDeck(id); model.libraryDeckRequest = nil } }
    }

    private var addMenu: some View {
        Menu {
            Button("New notebook",systemImage:"book.closed.badge.plus",action:newNotebook)
            if !model.library.liveDecks.isEmpty {
                Menu("Add source file",systemImage:"doc.badge.plus") {
                    ForEach(model.library.liveDecks) { deck in
                        Button(deck.name.replacingOccurrences(of:"::",with:" / ")) { beginImport(deck.id) }
                    }
                }
            }
        } label: { Image(systemName:"plus").font(.body.weight(.medium)).frame(width:44,height:44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("Add notebook or source file")
    }
    private func newNotebook() { model.creationPresented = true }
    private func newNotebook(in folder: String) {
        if model.deckCreationDraft.subject.isEmpty { model.deckCreationDraft.subject = folder }
        model.creationPresented = true
    }
    private func openDeck(_ id: String) { model.selectedDeckID = id; openedDeck = id }
    private func beginImport(_ deckID: String) { importDeckID = deckID; importing = true }
    private func importFiles(_ result: Result<[URL],Error>) async {
        guard let deckID = importDeckID else { return }
        do {
            for url in try result.get() {
                let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.read(url) }.value
                guard await model.perform({ try await $0.addDocument(document,to:deckID) }) else { return }
            }
            if let deck = model.library.liveDecks.first(where:{ $0.id == deckID }) { expanded.insert(deck.name) }
        } catch { model.error = "The source file could not be imported. \(error.localizedDescription)" }
        importDeckID = nil
    }
}

private struct LibraryExplorerNode: View {
    let node: LibraryFolder
    let depth: Int
    @Binding var expanded: Set<String>
    let searching: Bool
    let openDeck: (String) -> Void
    let openDocument: (LibraryDocument) -> Void
    let newNotebook: (String) -> Void
    let importFile: (String) -> Void
    let removeFile: (String,LibraryDocument) -> Void
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for:scheme) }
    private var documents: [LibraryDocument] { node.deck?.deck.documents ?? [] }
    private var branch: Bool { !node.children.isEmpty || !documents.isEmpty }
    private var isExpanded: Bool { searching || expanded.contains(node.path) }
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack(spacing:7) {
                if branch {
                    Button { toggle() } label: {
                        Image(systemName:isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size:10,weight:.semibold)).frame(width:18,height:44)
                    }.buttonStyle(.plain).accessibilityLabel(isExpanded ? "Collapse \(node.title)" : "Expand \(node.title)")
                } else { Color.clear.frame(width:18,height:44) }
                Button {
                    if let deck = node.deck { openDeck(deck.id) } else { toggle() }
                } label: {
                    HStack(spacing:8) {
                        Image(systemName:branch ? (isExpanded ? "folder.fill" : "folder") : "book.closed")
                            .font(.system(size:15)).foregroundStyle(palette.secondaryText).frame(width:20)
                        Text(node.title).font(.subheadline.weight(node.deck == nil ? .medium : .regular))
                            .lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                        if node.dueCount > 0 { Text("\(node.dueCount) due").font(.caption2).foregroundStyle(palette.accentInk) }
                    }.frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier(node.deck.map { "library-deck-" + $0.id } ?? "library-folder-" + node.path)
            }
            .padding(.leading,CGFloat(depth * 16))
            .contextMenu {
                if let deck = node.deck { Button("Open notebook") { openDeck(deck.id) }; Button("Add PDF or Markdown") { importFile(deck.id) } }
                Button("New notebook here") { newNotebook(node.path) }
            }
            if isExpanded {
                if let deck = node.deck {
                    ForEach(documents) { document in
                        Button { openDocument(document) } label: {
                            HStack(spacing:8) {
                                Image(systemName:document.kind == .pdf ? "doc.richtext" : "doc.text")
                                    .font(.system(size:14)).frame(width:20)
                                Text(document.name).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                                Text(document.kind == .pdf ? "PDF" : "MD").font(.caption2)
                            }.font(.subheadline).foregroundStyle(palette.secondaryText)
                                .frame(minHeight:44).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.leading,CGFloat((depth + 1) * 16 + 18))
                            .accessibilityIdentifier("library-file-" + document.id)
                            .contextMenu { Button("Remove file",role:.destructive) { removeFile(deck.id,document) } }
                    }
                }
                ForEach(node.children) { child in
                    LibraryExplorerNode(node:child,depth:depth + 1,expanded:$expanded,searching:searching,
                                        openDeck:openDeck,openDocument:openDocument,newNotebook:newNotebook,
                                        importFile:importFile,removeFile:removeFile)
                }
            }
        }
    }
    private func toggle() {
        if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
    }
}
#endif
