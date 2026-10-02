#if os(iOS)
import SwiftUI
import UniformTypeIdentifiers
import PhotosUI
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
    @State private var folderName = ""
    @State private var folderParent = ""
    @State private var showingFolderPrompt = false
    @State private var deleteFolderPath: String?
    @State private var choosingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoDeckID: String?
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var summaries: [LibraryDeckSummary] {
        LibraryDeckSummary.sorted(LibraryDeckSummary.make(in:model.library,now:model.now),by:.alphabetical,query:query)
    }
    private var nodes: [LibraryFolder] {
        let folders = model.library.folders ?? []
        return LibraryFolder.tree(summaries,explicitFolders:query.isEmpty ? folders : folders.filter { $0.localizedCaseInsensitiveContains(query) })
    }

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
                if model.library.liveDecks.isEmpty && nodes.isEmpty {
                    VStack(alignment:.leading,spacing:10) {
                        Image(systemName:"folder").font(.title2).foregroundStyle(palette.secondaryText)
                        Text("A place for what you learn").font(theme.font(.section))
                        Text("Create a folder or notebook, then add questions, PDFs, Markdown or images.")
                            .font(.subheadline).foregroundStyle(palette.secondaryText)
                        Button("Create notebook",action:newNotebook).font(.subheadline.weight(.semibold)).frame(minHeight:44)
                        Button("Create folder") { beginFolder(in:"") }.font(.subheadline).frame(minHeight:44)
                    }.padding(.top,30)
                } else if nodes.isEmpty {
                    Text("No matching notebooks or files").foregroundStyle(palette.secondaryText).padding(.top,30)
                } else {
                    LazyVStack(alignment:.leading,spacing:0) {
                        ForEach(nodes) { node in
                            LibraryExplorerNode(node:node,depth:0,expanded:$expanded,searching:!query.isEmpty,
                                                openDeck:openDeck,openDocument:{ openedDocument = $0 },
                                                newNotebook:newNotebook,newFolder:beginFolder,
                                                importFile:beginImport,importPhoto:beginPhoto,
                                                removeFolder:{ deleteFolderPath = $0 },
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
                      allowedContentTypes:[.pdf, UTType(filenameExtension:"md") ?? .plainText,.image],
                      allowsMultipleSelection:true) { result in Task { await importFiles(result) } }
        .photosPicker(isPresented:$choosingPhoto,selection:$selectedPhoto,matching:.images)
        .onChange(of:selectedPhoto) { _,photo in
            guard let photo,let deckID = photoDeckID else { return }
            Task {
                defer { selectedPhoto = nil; photoDeckID = nil }
                do {
                    guard let data = try await photo.loadTransferable(type:Data.self) else { throw EngramError.invalid("The selected photo could not be read.") }
                    let name = "Photo-" + UUID().uuidString.prefix(8) + ".jpg"
                    let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.image(data:data,name:String(name)) }.value
                    if await model.perform({ try await $0.addDocument(document,to:deckID) }),
                       let deck = model.library.liveDecks.first(where:{ $0.id == deckID }) { expanded.insert(deck.name) }
                } catch { model.error = "The photo could not be imported. \(error.localizedDescription)" }
            }
        }
        .alert("New folder",isPresented:$showingFolderPrompt) {
            TextField("Folder name",text:$folderName)
            Button("Create") {
                let name = folderName, parent = folderParent
                Task {
                    if await model.perform({ try await $0.createFolder(name:name,in:parent) }) {
                        if !parent.isEmpty { expanded.insert(parent) }
                    }
                }
            }
            Button("Cancel",role:.cancel) {}
        } message: { Text(folderParent.isEmpty ? "Add a folder to your Library." : "Add a folder inside \(folderParent.replacingOccurrences(of:"::",with:" / ")).") }
        .confirmationDialog("Delete empty folder?",isPresented:Binding(get:{ deleteFolderPath != nil },set:{ if !$0 { deleteFolderPath = nil } })) {
            if let path = deleteFolderPath {
                Button("Delete folder",role:.destructive) {
                    Task { _ = await model.perform { try await $0.removeEmptyFolder(path:path) }; deleteFolderPath = nil }
                }
            }
            Button("Cancel",role:.cancel) { deleteFolderPath = nil }
        } message: { Text("Folders containing notebooks or subfolders must be emptied first.") }
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
            Button("New folder",systemImage:"folder.badge.plus") { beginFolder(in:"") }
            Button("New notebook",systemImage:"book.closed.badge.plus",action:newNotebook)
            if !model.library.liveDecks.isEmpty {
                Menu("Add source file",systemImage:"doc.badge.plus") {
                    ForEach(model.library.liveDecks) { deck in
                        Button(deck.name.replacingOccurrences(of:"::",with:" / ")) { beginImport(deck.id) }
                    }
                }
                Menu("Add image from Photos",systemImage:"photo.on.rectangle") {
                    ForEach(model.library.liveDecks) { deck in
                        Button(deck.name.replacingOccurrences(of:"::",with:" / ")) { beginPhoto(deck.id) }
                    }
                }
            }
        } label: { Image(systemName:"plus").font(.body.weight(.medium)).frame(width:44,height:44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("Add notebook or source file")
    }
    private func newNotebook() { model.creationPresented = true }
    private func beginFolder(in parent: String) { folderParent = parent; folderName = ""; showingFolderPrompt = true }
    private func newNotebook(in folder: String) {
        if model.deckCreationDraft.subject.isEmpty { model.deckCreationDraft.subject = folder }
        model.creationPresented = true
    }
    private func openDeck(_ id: String) { model.selectedDeckID = id; openedDeck = id }
    private func beginImport(_ deckID: String) { importDeckID = deckID; importing = true }
    private func beginPhoto(_ deckID: String) { photoDeckID = deckID; selectedPhoto = nil; choosingPhoto = true }
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
    let newFolder: (String) -> Void
    let importFile: (String) -> Void
    let importPhoto: (String) -> Void
    let removeFolder: (String) -> Void
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
                        Image(systemName:node.deck == nil || branch ? (isExpanded ? "folder.fill" : "folder") : "book.closed")
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
                if let deck = node.deck { Button("Add image from Photos") { importPhoto(deck.id) } }
                Button("New notebook here") { newNotebook(node.path) }
                Button("New folder here") { newFolder(node.path) }
                if node.isExplicit && node.deck == nil && node.children.isEmpty {
                    Button("Delete empty folder",role:.destructive) { removeFolder(node.path) }
                }
            }
            if isExpanded {
                if let deck = node.deck {
                    ForEach(documents) { document in
                        Button { openDocument(document) } label: {
                            HStack(spacing:8) {
                                Image(systemName:document.kind == .pdf ? "doc.richtext" : document.kind == .image ? "photo" : "doc.text")
                                    .font(.system(size:14)).frame(width:20)
                                Text(document.name).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                                Text(document.kind == .pdf ? "PDF" : document.kind == .image ? "IMG" : "MD").font(.caption2)
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
                                        newFolder:newFolder,importFile:importFile,importPhoto:importPhoto,
                                        removeFolder:removeFolder,removeFile:removeFile)
                }
            }
        }
    }
    private func toggle() {
        if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
    }
}
#endif
