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
    @Environment(\.engramWorkspaceLayout) private var workspace
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var expanded = Set<String>()
    @State private var openedDeck: String?
    @State private var openedDocument: LibraryDocument?
    @State private var importing = false
    @State private var importDeckID: String?
    @State private var importFolderPath: String?
    @State private var deleteDocument: (deckID: String?, document: LibraryDocument)?
    @State private var folderName = ""
    @State private var folderParent = ""
    @State private var showingFolderPrompt = false
    @State private var deleteFolderPath: String?
    @State private var choosingPhoto = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoDeckID: String?
    @State private var photoFolderPath: String?
    @State private var rootDropTargeted = false
    @State private var testingSamplesPresented = false
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var summaries: [LibraryDeckSummary] {
        LibraryDeckSummary.sorted(LibraryDeckSummary.make(in:model.library,now:model.now),by:.alphabetical,query:query)
    }
    private var nodes: [LibraryFolder] {
        let folders = model.library.folders ?? []
        let matchedFiles = (model.library.folderDocuments ?? []).filter { $0.document.name.localizedCaseInsensitiveContains(query) }
        let filePaths = matchedFiles.map(\.folderPath)
        return LibraryFolder.tree(summaries,explicitFolders:query.isEmpty ? folders : folders.filter { folder in
            folder.localizedCaseInsensitiveContains(query) || filePaths.contains(where: { $0 == folder || $0.hasPrefix(folder + "::") })
        })
    }
    private var rootDocuments: [LibraryFolderDocument] { folderDocuments(for:"") }
    private func folderDocuments(for path: String) -> [LibraryFolderDocument] {
        (model.library.folderDocuments ?? []).filter { $0.folderPath == path && (query.isEmpty || $0.document.name.localizedCaseInsensitiveContains(query)) }
            .sorted { $0.document.name.localizedStandardCompare($1.document.name) == .orderedAscending }
    }

    var body: some View {
        Group {
            if workspace {
                HStack(alignment: .top, spacing: 0) {
                    explorerContent.frame(width: 280)
                    Divider()
                    Group {
                        if let id = openedDeck {
                            DeckOverviewView(model: model, deckID: id)
                                .id(id)
                        } else {
                            ContentUnavailableView("Choose a notebook", systemImage: "book.closed",
                                description: Text("Your files stay alongside your notes and review outlook."))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.accessibilityIdentifier("workspace-library")
            } else { explorerContent }
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $testingSamplesPresented) { TestingLibraryImportView(model: model) }
        .onChange(of: model.libraryPresentationEpoch) { _, _ in openedDeck = nil; openedDocument = nil; expanded = []; query = "" }
        .refreshable { await model.refresh() }
        .navigationDestination(item:Binding(get:{ workspace ? nil : openedDeck },set:{ openedDeck = $0 })) { id in LibraryDeckDestination(model:model,deckID:id) }
        .sheet(item:$openedDocument,onDismiss:{ model.visibleLibraryDocumentID = nil }) { document in LibraryDocumentReader(document:document) }
        .fileImporter(isPresented:$importing,
                      allowedContentTypes:[.pdf, UTType(filenameExtension:"md") ?? .plainText,.image],
                      allowsMultipleSelection:true) { result in Task { await importFiles(result) } }
        .photosPicker(isPresented:$choosingPhoto,selection:$selectedPhoto,matching:.images)
        .onChange(of:selectedPhoto) { _,photo in
            guard let photo, photoDeckID != nil || photoFolderPath != nil else { return }
            Task {
                defer { selectedPhoto = nil; photoDeckID = nil; photoFolderPath = nil }
                do {
                    guard let data = try await photo.loadTransferable(type:Data.self) else { throw EngramError.invalid("The selected photo could not be read.") }
                    let name = "Photo-" + UUID().uuidString.prefix(8) + ".jpg"
                    let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.image(data:data,name:String(name)) }.value
                    if let deckID = photoDeckID {
                        if await model.perform({ try await $0.addDocument(document,to:deckID) }),
                           let deck = model.library.liveDecks.first(where:{ $0.id == deckID }) { expanded.insert(deck.name) }
                    } else if let path = photoFolderPath {
                        _ = await model.perform { try await $0.addDocument(document,toFolder:path) }
                        expanded.insert(path)
                    }
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
                    Task {
                        if let deckID = target.deckID { _ = await model.perform { try await $0.removeDocument(id:target.document.id,from:deckID) } }
                        else { _ = await model.perform { try await $0.removeFolderDocument(id:target.document.id) } }
                        deleteDocument = nil
                    }
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

    private var explorerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workspace ? "Files" : "Library").font(workspace ? .headline : .largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    addMenu
                }
                LibrarySpacePicker(model: model)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(workspace ? "" : "FILES").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text("Drop here to move to Library root").font(.caption2).foregroundStyle(palette.secondaryText).opacity(rootDropTargeted ? 1 : 0)
                    }
                    .frame(minHeight:32)
                    .contentShape(Rectangle())
                    .background(rootDropTargeted ? palette.selection : .clear)
                    .dropDestination(for:String.self) { items,_ in handleDrop(items.first,to:.folder("")) } isTargeted: { rootDropTargeted = $0 }
                    HStack(spacing: 9) {
                        Image(systemName:"magnifyingglass").foregroundStyle(palette.secondaryText)
                        TextField("Find a notebook or file",text:$query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Clear search") }
                    }.font(.subheadline).frame(minHeight:44)
                    Divider()
                }
                if model.library.liveDecks.isEmpty && nodes.isEmpty && (model.library.folderDocuments ?? []).isEmpty {
                    VStack(alignment:.leading,spacing:10) {
                        Image(systemName:"folder").font(.title2).foregroundStyle(palette.secondaryText)
                        Text("A place for what you learn").font(theme.font(.section))
                        Text("Create a folder or notebook, then add questions, PDFs, Markdown or images.")
                            .font(.subheadline).foregroundStyle(palette.secondaryText)
                        Button("Create notebook",action:newNotebook).font(.subheadline.weight(.semibold)).frame(minHeight:44)
                        Button("Create folder") { beginFolder(in:"") }.font(.subheadline).frame(minHeight:44)
                    }.padding(.top,30)
                } else if nodes.isEmpty && rootDocuments.isEmpty {
                    Text("No matching notebooks or files").foregroundStyle(palette.secondaryText).padding(.top,30)
                } else {
                    LazyVStack(alignment:.leading,spacing:0) {
                        ForEach(rootDocuments) { item in
                            folderFileRow(item,depth:0)
                        }
                        ForEach(nodes) { node in
                            LibraryExplorerNode(model:model,node:node,depth:0,expanded:$expanded,searching:!query.isEmpty,
                                                folderDocuments:folderDocuments(for:node.path),
                                                filesInFolder:folderDocuments,
                                                openDeck:openDeck,openDocument:openDocument,
                                                newNotebook:newNotebook,newFolder:beginFolder,
                                                importFile:beginImport,importPhoto:beginPhoto,
                                                importFolderFile:beginFolderImport,importFolderPhoto:beginFolderPhoto,
                                                suspendDeck:{ id, suspended in Task { _ = await model.perform { try await $0.setDeckSuspended(id:id,suspended:suspended) } } },
                                                deleteDeck:{ model.deleteDeck = $0 },
                                                removeFolder:{ deleteFolderPath = $0 },
                                                removeFile:{ deckID,document in deleteDocument = (deckID,document) },
                                                move:handleDrop)
                        }
                    }
                }
                if let importAction {
                    Button("Import or export library",action:importAction)
                        .font(.caption).foregroundStyle(palette.secondaryText).frame(minHeight:44)
                        .accessibilityIdentifier("library-import-export")
                }
            }
            .padding(.horizontal,20).padding(.top,8).padding(.bottom,28)
            .frame(maxWidth: workspace ? .infinity : 760).frame(maxWidth:.infinity)
        }
    }

    private var addMenu: some View {
        Menu {
            Button("New folder",systemImage:"folder.badge.plus") { beginFolder(in:"") }
            Button("New notebook",systemImage:"book.closed.badge.plus",action:newNotebook)
            Button("Testing samples", systemImage: "checklist") { testingSamplesPresented = true }
            Button("Add source file to Library",systemImage:"doc.badge.plus") { beginFolderImport("") }
            Button("Add image to Library",systemImage:"photo.on.rectangle") { beginFolderPhoto("") }
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
            .buttonStyle(.plain).accessibilityLabel("Add notebook or source file").accessibilityIdentifier("library-add-menu")
    }
    private func newNotebook() { model.creationPresented = true }
    private func beginFolder(in parent: String) { folderParent = parent; folderName = ""; showingFolderPrompt = true }
    private func newNotebook(in folder: String) {
        if model.deckCreationDraft.subject.isEmpty { model.deckCreationDraft.subject = folder }
        model.creationPresented = true
    }
    private func openDeck(_ id: String) { model.selectedDeckID = id; openedDeck = id }
    private func openDocument(_ document: LibraryDocument) { model.visibleLibraryDocumentID = document.id; openedDocument = document }
    private func beginImport(_ deckID: String) { importFolderPath = nil; importDeckID = deckID; importing = true }
    private func beginFolderImport(_ path: String) { importDeckID = nil; importFolderPath = path; importing = true }
    private func beginPhoto(_ deckID: String) { photoFolderPath = nil; photoDeckID = deckID; selectedPhoto = nil; choosingPhoto = true }
    private func beginFolderPhoto(_ path: String) { photoDeckID = nil; photoFolderPath = path; selectedPhoto = nil; choosingPhoto = true }
    private func importFiles(_ result: Result<[URL],Error>) async {
        guard importDeckID != nil || importFolderPath != nil else { return }
        do {
            for url in try result.get() {
                let document = try await Task.detached(priority:.userInitiated) { try LibraryDocumentImport.read(url) }.value
                let saved: Bool
                if let deckID = importDeckID { saved = await model.perform { try await $0.addDocument(document,to:deckID) } }
                else { saved = await model.perform { try await $0.addDocument(document,toFolder:importFolderPath ?? "") } }
                guard saved else { return }
            }
            if let deckID = importDeckID,let deck = model.library.liveDecks.first(where:{ $0.id == deckID }) { expanded.insert(deck.name) }
            if let path = importFolderPath { expanded.insert(path) }
        } catch { model.error = "The source file could not be imported. \(error.localizedDescription)" }
        importDeckID = nil; importFolderPath = nil
    }
    private func handleDrop(_ payload: String?,to destination: StudyService.DocumentDestination) -> Bool {
        guard let payload else { return false }
        if payload.hasPrefix("engram-file:") {
            let id = String(payload.dropFirst("engram-file:".count))
            Task { _ = await model.perform { try await $0.moveDocument(id:id,to:destination) } }
            return true
        }
        guard case .folder(let path) = destination else { return false }
        if payload.hasPrefix("engram-deck:") {
            let id = String(payload.dropFirst("engram-deck:".count))
            Task { _ = await model.perform { try await $0.moveDeck(id:id,toFolder:path) } }
            expanded.insert(path)
            return true
        }
        if payload.hasPrefix("engram-folder:") {
            let source = String(payload.dropFirst("engram-folder:".count))
            Task { _ = await model.perform { try await $0.moveFolder(path:source,toFolder:path) } }
            expanded.insert(path)
            return true
        }
        return false
    }
    private func folderFileRow(_ item: LibraryFolderDocument,depth: Int) -> some View {
        Button { openDocument(item.document) } label: {
            Label(item.document.name,systemImage:item.document.kind == .pdf ? "doc.richtext" : item.document.kind == .image ? "photo" : "doc.text")
                .font(.subheadline).foregroundStyle(palette.secondaryText).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
                .padding(.leading,CGFloat(depth * 16 + 18))
        }
        .buttonStyle(.plain).accessibilityIdentifier("library-file-" + item.id)
        .draggable("engram-file:" + item.id)
        .contextMenu { Button("Open file") { openDocument(item.document) }; Button("Delete file",role:.destructive) { deleteDocument = (nil,item.document) } }
    }
}

private struct LibraryExplorerNode: View {
    let model: EngramModel
    let node: LibraryFolder
    let depth: Int
    @Binding var expanded: Set<String>
    let searching: Bool
    let folderDocuments: [LibraryFolderDocument]
    let filesInFolder: (String) -> [LibraryFolderDocument]
    let openDeck: (String) -> Void
    let openDocument: (LibraryDocument) -> Void
    let newNotebook: (String) -> Void
    let newFolder: (String) -> Void
    let importFile: (String) -> Void
    let importPhoto: (String) -> Void
    let importFolderFile: (String) -> Void
    let importFolderPhoto: (String) -> Void
    let suspendDeck: (String, Bool) -> Void
    let deleteDeck: (Deck) -> Void
    let removeFolder: (String) -> Void
    let removeFile: (String?,LibraryDocument) -> Void
    let move: (String?,StudyService.DocumentDestination) -> Bool
    @State private var dropTargeted = false
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for:scheme) }
    private var documents: [LibraryDocument] { node.deck?.deck.documents ?? [] }
    private var branch: Bool { !node.children.isEmpty || !documents.isEmpty || !folderDocuments.isEmpty }
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
                        if node.deck?.deck.studySuspended == true { Image(systemName:"pause.circle").foregroundStyle(palette.secondaryText).accessibilityLabel("Suspended") }
                        else if node.dueCount > 0 { Text("\(node.dueCount) due").font(.caption2).foregroundStyle(palette.accentInk) }
                    }.frame(minHeight:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier(node.deck.map { "library-deck-" + $0.id } ?? "library-folder-" + node.path)
            }
            .padding(.leading,CGFloat(depth * 16))
            .background(dropTargeted ? palette.selection : .clear)
            .draggable(node.deck.map { "engram-deck:" + $0.id } ?? "engram-folder:" + node.path)
            .dropDestination(for:String.self) { items,_ in
                move(items.first,node.deck.map { .notebook($0.id) } ?? .folder(node.path))
            } isTargeted: { dropTargeted = $0 }
            .contextMenu {
                if let deck = node.deck { Button("Open notebook") { openDeck(deck.id) }; Button("Add PDF or Markdown") { importFile(deck.id) } }
                if let deck = node.deck {
                    Button("Add image from Photos") { importPhoto(deck.id) }
                    Button(deck.deck.studySuspended == true ? "Resume deck" : "Suspend deck",systemImage:deck.deck.studySuspended == true ? "play" : "pause") { suspendDeck(deck.id,deck.deck.studySuspended != true) }
                    MoveDeckToLibraryMenu(model: model, deckID: deck.id)
                    Button("Delete deck",role:.destructive) { deleteDeck(deck.deck) }
                }
                if node.deck == nil {
                    Button("Add source file") { importFolderFile(node.path) }
                    Button("Add image from Photos") { importFolderPhoto(node.path) }
                }
                Button("New notebook here") { newNotebook(node.path) }
                Button("New folder here") { newFolder(node.path) }
                if node.isExplicit && node.deck == nil && node.children.isEmpty {
                    Button("Delete empty folder",role:.destructive) { removeFolder(node.path) }
                }
            }
            .modifier(DeckSuspendSwipe(enabled:node.deck != nil,suspended:node.deck?.deck.studySuspended == true,palette:palette) {
                if let deck = node.deck { suspendDeck(deck.id,deck.deck.studySuspended != true) }
            })
            if isExpanded {
                ForEach(folderDocuments) { item in
                    Button { openDocument(item.document) } label: {
                        HStack(spacing:8) {
                            Image(systemName:item.document.kind == .pdf ? "doc.richtext" : item.document.kind == .image ? "photo" : "doc.text")
                                .font(.system(size:14)).frame(width:20)
                            Text(item.document.name).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                        }.font(.subheadline).foregroundStyle(palette.secondaryText).frame(minHeight:44).contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.leading,CGFloat((depth + 1) * 16 + 18))
                        .accessibilityIdentifier("library-file-" + item.id)
                        .draggable("engram-file:" + item.id)
                        .contextMenu { Button("Open file") { openDocument(item.document) }; Button("Delete file",role:.destructive) { removeFile(nil,item.document) } }
                }
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
                            .draggable("engram-file:" + document.id)
                            .contextMenu { Button("Open file") { openDocument(document) }; Button("Delete file",role:.destructive) { removeFile(deck.id,document) } }
                    }
                }
                ForEach(node.children) { child in
                    LibraryExplorerNode(model:model,node:child,depth:depth + 1,expanded:$expanded,searching:searching,
                                        folderDocuments:filesInFolder(child.path),filesInFolder:filesInFolder,
                                        openDeck:openDeck,openDocument:openDocument,newNotebook:newNotebook,
                                        newFolder:newFolder,importFile:importFile,importPhoto:importPhoto,
                                        importFolderFile:importFolderFile,importFolderPhoto:importFolderPhoto,
                                        suspendDeck:suspendDeck,deleteDeck:deleteDeck,removeFolder:removeFolder,removeFile:removeFile,move:move)
                }
            }
        }
    }
    private func toggle() {
        if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
    }
}
/// The explorer is a recursive scroll view, so it needs its own horizontal action reveal.
private struct DeckSuspendSwipe: ViewModifier {
    let enabled: Bool
    let suspended: Bool
    let palette: EngramPalette
    let action: () -> Void
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        if enabled {
            ZStack(alignment: .trailing) {
                if revealed {
                    Button {
                        revealed = false
                        action()
                    } label: {
                        Label(suspended ? "Resume" : "Suspend", systemImage: suspended ? "play" : "pause")
                            .font(.caption).labelStyle(.titleAndIcon).frame(width: 100).frame(minHeight: 44)
                            .foregroundStyle(palette.primaryText).background(palette.selection)
                    }.buttonStyle(.plain).accessibilityLabel(suspended ? "Resume deck" : "Suspend deck")
                }
                content.background(palette.canvas).offset(x: revealed ? -104 : 0)
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: revealed)
            .highPriorityGesture(DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.7 else { return }
                if value.translation.width < -40 { revealed = true }
                else if value.translation.width > 40 { revealed = false }
            })
            .onChange(of: suspended) { _, _ in revealed = false }
        } else { content }
    }
}
#endif
