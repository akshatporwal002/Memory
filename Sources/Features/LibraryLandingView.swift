#if os(iOS)
import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import LearningCore
import StudyApplication
import DesignSystem

/// iPhone-first collection with compact covers and a text-only directory.
struct LibraryLandingView: View {
    @Bindable var model: EngramModel
    var importAction: (() -> Void)?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.engramScreenshotCapture) private var capturing
    @AppStorage("engram.library.sort.v1") private var sortRaw = LibrarySort.nextReview.rawValue
    @AppStorage("engram.library.folders.v1") private var showFolders = false
    @State private var query = ""
    @State private var entries: [LibraryDeckSummary] = []
    @State private var retention: [String:Double] = [:]
    @State private var expanded = Set<String>()
    @State private var openedDeck: String?
    @State private var photo: PhotosPickerItem?
    @State private var coverDeckID: String?
    @State private var choosingCover = false
    @State private var savingCover = false
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .nextReview }
    private var results: [LibraryDeckSummary] { LibraryDeckSummary.sorted(entries, by: sort, query: query) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if model.loaded {
                    if entries.isEmpty { emptyLibrary }
                    else {
                        searchField
                        displayControls
                        if results.isEmpty { noResults }
                        else { listContent }
                    }
                } else { ProgressView("Opening your decks…").frame(maxWidth: .infinity).padding(.vertical, 60) }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 32)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.refresh(); reload() }
        .navigationDestination(item: $openedDeck) { id in
            LibraryDeckDestination(model: model, deckID: id)
        }
        .photosPicker(isPresented: $choosingCover, selection: $photo, matching: .images)
        .task(id: photo) { await savePickedCover() }
        .task(id:"\(model.library.revision)-\(model.loaded)") {
            let library = model.library,now = model.now
            var values: [String:Double] = [:]
            for deck in library.liveDecks {
                let outlook = await model.service.memoryOutlook(for:deck,in:library,now:now)
                guard !Task.isCancelled else { return }
                if let average = outlook.average.first { values[deck.id] = average }
            }
            retention = values
        }
        .onAppear {
            reload()
            if let id = model.libraryDeckRequest { open(id); model.libraryDeckRequest = nil }
            openRequestedCoverPicker()
        }
        .onChange(of:model.coverPickerDeckID) { _, _ in openRequestedCoverPicker() }
        .onChange(of: model.library.revision) { _, _ in if openedDeck == nil && !savingCover { reload() } }
        .onChange(of: model.loaded) { _, _ in reload() }
        .onChange(of: openedDeck) { _, id in if id == nil { reload() } }
        .onChange(of: model.libraryDeckRequest) { _, id in
            if let id { open(id); model.libraryDeckRequest = nil }
        }
        // Screenshot tours already select a deck in their isolated model.
        .onChange(of: model.selectedDeckID) { _, id in if capturing, let id { open(id) } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Library").font(.largeTitle.bold()); Spacer(); newDeckButton }
                VStack(alignment: .leading, spacing: 12) { Text("Library").font(.largeTitle.bold()); newDeckButton }
            }
            if !entries.isEmpty {
                let count = entries.reduce(0) { $0 + $1.cardCount }
                Text("\(entries.count) \(entries.count == 1 ? "deck" : "decks") · \(cardCount(count))")
                    .font(.subheadline).foregroundStyle(palette.secondaryText)
            }
        }
    }
    private var newDeckButton: some View {
        Button { model.creationPresented = true } label: {
            Label(model.deckCreationDraft.isEmpty ? "New deck" : "Resume draft", systemImage: model.deckCreationDraft.isEmpty ? "plus" : "square.and.pencil")
        }
            .buttonStyle(EngramButtonStyle(.secondary)).disabled(model.busy)
            .accessibilityIdentifier("library-new-deck")
    }
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.secondaryText)
            TextField("Search decks or questions", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("library-search")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear search").frame(minWidth: 44, minHeight: 44)
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 48)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(palette.hairline, lineWidth: 1) }
    }
    private var displayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { Spacer(minLength: 0); sortMenu }
                VStack(alignment: .leading, spacing: 12) { sortMenu }
            }
            Toggle("Show folders", isOn: $showFolders).font(.subheadline)
                .tint(palette.accentInk).accessibilityIdentifier("library-folders")
        }
    }
    private var sortMenu: some View {
        Menu {
            Picker("Sort decks", selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { Text($0.title).tag($0.rawValue) }
            }
        } label: { Label(sort.title, systemImage: "arrow.up.arrow.down").font(.subheadline).frame(minHeight: 44) }
            .accessibilityLabel("Sort: \(sort.title)").accessibilityIdentifier("library-sort")
    }
    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                sampleCover("Your", "first deck").rotationEffect(.degrees(-4))
                sampleCover("A new", "subject").rotationEffect(.degrees(4))
            }.padding(.vertical, 12).accessibilityHidden(true)
            Text("Make room for what\nyou want to remember.").font(theme.font(.title))
            Text("Create a deck for a subject, a course, or a curiosity. Your collection starts here.")
                .foregroundStyle(palette.secondaryText)
            if let importAction {
                Button(action: importAction) { Label("Import existing decks", systemImage: "square.and.arrow.down") }
                    .buttonStyle(EngramButtonStyle(.secondary))
            }
        }.padding(.top, 16)
    }
    private func sampleCover(_ first: String, _ second: String) -> some View {
        VStack(alignment: .leading) {
            Image(systemName: "rectangle.stack").font(.title3)
            Spacer(minLength: 22)
            Text(first).font(.subheadline)
            Text(second).font(theme.font(.section))
        }.padding(18).frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
            .foregroundStyle(palette.primaryText)
            .background(palette.selection, in: RoundedRectangle(cornerRadius: 16))
    }
    private var noResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.largeTitle)
            Text("No matching decks").font(.headline)
            Text("Try a deck name, subject, or words from a question.").foregroundStyle(palette.secondaryText)
            Button("Clear search") { query = "" }.frame(minHeight: 44)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 40)
    }
    @ViewBuilder private var listContent: some View {
        LazyVStack(spacing: 0) {
            if showFolders {
                ForEach(LibraryFolder.tree(results)) { node in
                    LibraryTreeRow(node: node, expanded: $expanded, searching: !query.isEmpty) { entry in listRow(entry) }
                }
            } else { ForEach(results) { listRow($0) } }
        }
    }
    private func listRow(_ entry: LibraryDeckSummary) -> some View {
        HStack(spacing: 0) {
            Button { open(entry.id) } label: {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { directoryName(entry); Spacer(minLength: 8); directoryStatus(entry).fixedSize() }
                    VStack(alignment: .leading, spacing: 4) { directoryName(entry); directoryStatus(entry) }
                }.contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).accessibilityIdentifier("library-deck-\(entry.id)")
            deckMenu(entry).frame(width: 44, height: 44)
        }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() }
    }
    private func directoryName(_ entry: LibraryDeckSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LibraryRetentionIndicator(average:retention[entry.deck.id])
            Text(entry.title).font(theme.font(.control)).fixedSize(horizontal: false, vertical: true)
            if !showFolders && !entry.folder.isEmpty {
                Text(entry.folder.replacingOccurrences(of: "::", with: " / ")).font(.caption2).foregroundStyle(palette.secondaryText)
            }
        }
    }
    private func directoryStatus(_ entry: LibraryDeckSummary) -> some View {
        HStack(spacing: 5) {
            Text(cardCount(entry.cardCount)).foregroundStyle(palette.secondaryText)
            if entry.dueCount > 0 { Text("· \(entry.dueCount) due").foregroundStyle(palette.accentInk) }
            else if entry.newCount > 0 { Text("· \(entry.newCount) new").foregroundStyle(palette.accentInk) }
            else if let date = entry.nextReview {
                Text("· " + date.formatted(.dateTime.month(.abbreviated).day())).foregroundStyle(palette.secondaryText)
            }
        }.font(.caption).monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityValue(entry.limitReached ? "Daily limit reached" : "")
    }
    private func cardCount(_ count: Int) -> String { "\(count) \(count == 1 ? "card" : "cards")" }
    private func reviewStatus(_ entry: LibraryDeckSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if entry.dueCount > 0 { Text("\(entry.dueCount) due").foregroundStyle(palette.accentInk) }
            else if entry.newCount > 0 { Text("\(entry.newCount) new").foregroundStyle(palette.accentInk) }
            else if let date = entry.nextReview {
                Text(date, format: .dateTime.month(.abbreviated).day()).foregroundStyle(palette.secondaryText)
                    .accessibilityLabel("Next review \(date.formatted(date: .abbreviated, time: .shortened))")
            } else { Text(entry.cardCount == 0 ? "No cards yet" : "Nothing to review").foregroundStyle(palette.secondaryText) }
            if entry.limitReached { Text("Daily limit reached").foregroundStyle(palette.secondaryText) }
            if savingCover && coverDeckID == entry.id { ProgressView("Saving cover…") }
        }.font(.caption.weight(.medium))
    }
    private func deckMenu(_ entry: LibraryDeckSummary) -> some View {
        Menu {
            Button("Open deck") { open(entry.id) }
            Button("Questions", systemImage: "rectangle.stack") { model.questionsDeckID = entry.id }
            Button("Notes", systemImage: "book.pages") { model.notebookWritingOnly = true; model.notebookDeckID = entry.id }
            Button("Choose cover photo…", systemImage: "photo") {
                coverDeckID = entry.id; photo = nil; choosingCover = true
            }
            if entry.deck.coverMediaName != nil {
                Button("Remove cover photo", systemImage: "photo.badge.minus") {
                    Task { _ = await model.perform { try await $0.setDeckCover(id: entry.id, jpeg: nil) }; reload() }
                }
            }
        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }
            .disabled(model.busy || savingCover).accessibilityLabel("Options for \(entry.title)")
    }
    private func coverData(_ deck: Deck) -> Data? { model.library.media.first { $0.name == deck.coverMediaName }?.data }
    private func openRequestedCoverPicker() {
        guard let id = model.coverPickerDeckID,model.library.liveDecks.contains(where: { $0.id == id }) else { return }
        coverDeckID = id; photo = nil; model.coverPickerDeckID = nil; choosingCover = true
    }
    private func reload() { entries = LibraryDeckSummary.make(in: model.library, now: Date()) }
    private func open(_ id: String) {
        model.selectedDeckID = id; model.search = ""; openedDeck = id
    }
    private func savePickedCover() async {
        guard let photo, let id = coverDeckID else { return }
        savingCover = true
        defer { savingCover = false; reload() }
        do {
            guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 40 * 1_024 * 1_024 else {
                throw EngramError.invalid("Choose an image smaller than 40 MB.")
            }
            try Task.checkCancellation()
            let jpeg = try await Task.detached(priority: .userInitiated) { try DeckCoverImage.jpeg(from: data) }.value
            try Task.checkCancellation()
            _ = await model.perform { try await $0.setDeckCover(id: id, jpeg: jpeg) }
        } catch is CancellationError { }
        catch { model.error = "The cover could not be saved. \(error.localizedDescription)" }
    }
}

private struct LibraryRetentionIndicator: View {
    let average: Double?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Group {
            if let average {
                HStack(spacing: 5) {
                    Capsule().fill(theme.palette(for: scheme).accentInk.opacity(0.2)).frame(width: 36,height: 2)
                        .overlay(alignment: .leading) { Capsule().fill(theme.palette(for: scheme).accentInk).frame(width: 36 * average,height: 2) }
                    Text(average, format: .percent.precision(.fractionLength(0))).font(.caption2).foregroundStyle(theme.palette(for: scheme).secondaryText)
                }.accessibilityElement(children: .ignore).accessibilityLabel("Estimated retention \(Int(average * 100)) percent")
            }
        }
    }
}

private struct LibraryTreeRow<Row: View>: View {
    let node: LibraryFolder
    @Binding var expanded: Set<String>
    let searching: Bool
    @ViewBuilder let row: (LibraryDeckSummary) -> Row
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !node.children.isEmpty {
                Button {
                    if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) }
                } label: {
                    HStack {
                        Image(systemName: expanded.contains(node.path) || searching ? "chevron.down" : "chevron.right").font(.caption)
                        Text(node.title)
                        Spacer(minLength: 4)
                        Text("\(node.deckCount)").font(.caption).foregroundStyle(.secondary)
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(expanded.contains(node.path) || searching ? "Expanded" : "Collapsed")
                if expanded.contains(node.path) || searching {
                    VStack(spacing: 0) {
                        if let entry = node.deck { row(entry) }
                        ForEach(node.children) { child in LibraryTreeRow(node: child, expanded: $expanded, searching: searching, row: row) }
                    }.padding(.leading, 12)
                }
            } else if let entry = node.deck { row(entry) }
        }
    }
}

private struct DeckCoverView: View {
    let deck: Deck
    let data: Data?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var decoded: UIImage?
    private var letters: String {
        let name = deck.name.components(separatedBy: "::").last ?? deck.name
        return name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
    var body: some View {
        let palette = theme.palette(for: scheme)
        let dark = deck.id.utf8.reduce(0) { ($0 + Int($1)) % 3 } == 0
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                if let decoded {
                    Image(uiImage: decoded).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    (dark ? palette.anchor : palette.selection)
                    Rectangle().fill(palette.accent.opacity(0.25)).frame(width: 6).frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(letters).font(.system(size: 30, weight: .medium, design: theme == .warm ? .serif : .rounded))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        Spacer(minLength: 44)
                    }.padding(.horizontal, 14).padding(.vertical, 12).foregroundStyle(dark ? palette.onAnchor : palette.primaryText)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }.accessibilityHidden(true)
            .task(id: deck.coverMediaName) { decoded = data.flatMap(UIImage.init(data:)) }
    }
}

private enum DeckCoverImage {
    static func jpeg(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 720
              ] as CFDictionary) else { throw EngramError.invalid("This image format could not be opened.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw EngramError.invalid("The cover could not be converted.")
        }
        // Re-encode pixels only; do not retain location or original photo metadata.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), output.length <= 1_024 * 1_024 else { throw EngramError.invalid("The cover is too large.") }
        return output as Data
    }
}

private struct LibraryDeckDestination: View {
    @Bindable var model: EngramModel
    let deckID: String
    var body: some View {
        Group {
            if let deck = model.library.liveDecks.first(where: { $0.id == deckID }) {
                DeckOverviewView(model: model, deckID: deckID)
                    .navigationTitle(deck.name.components(separatedBy: "::").last ?? deck.name)
            } else { ContentUnavailableView("Deck unavailable", systemImage: "rectangle.stack", description: Text("This deck may have been removed.")) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .engramCanvas()
        .onAppear { model.selectedDeckID = deckID }
    }
}

#endif
