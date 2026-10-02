import Foundation

public enum LibraryDocumentKind: String, Codable, Sendable {
    case pdf, markdown, image
}

/// A source file attached to a notebook. Extracted text is indexed for retrieval;
/// the original bytes are kept for faithful offline reading and private backup.
public struct LibraryDocument: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var kind: LibraryDocumentKind
    public var pages: [PDFPageText]
    public var originalData: Data
    public var addedAt: Date

    public init(id: String = UUID().uuidString, name: String, kind: LibraryDocumentKind,
                pages: [PDFPageText], originalData: Data, addedAt: Date = Date()) {
        self.id = id; self.name = name; self.kind = kind
        self.pages = pages; self.originalData = originalData; self.addedAt = addedAt
    }

    public func validate() throws {
        guard UUID(uuidString: id) != nil,
              !name.isEmpty, name.utf8.count <= 240,
              !name.contains("/"), !name.contains("\\"),
              (kind == .image ? (0...1) : (1...300)).contains(pages.count),
              Set(pages.map(\.number)).count == pages.count,
              pages.allSatisfy({ $0.number > 0 }),
              pages.reduce(0, { $0 + $1.text.utf8.count }) <= 2_000_000,
              (kind == .image || pages.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })) else {
            throw EngramError.invalid("Choose a readable source file.")
        }
        switch kind {
        case .pdf:
            guard originalData.count <= 25_000_000, originalData.starts(with: Data("%PDF-".utf8)) else {
                throw EngramError.invalid("Choose a PDF smaller than 25 MB.")
            }
        case .markdown:
            guard originalData.count <= 2_000_000,
                  String(data: originalData, encoding: .utf8) != nil,
                  name.lowercased().hasSuffix(".md") || name.lowercased().hasSuffix(".markdown") else {
                throw EngramError.invalid("Choose a UTF-8 Markdown file smaller than 2 MB.")
            }
        case .image:
            guard originalData.count <= 10_000_000,
                  originalData.starts(with: [0xFF, 0xD8, 0xFF]),
                  name.lowercased().hasSuffix(".jpg") || name.lowercased().hasSuffix(".jpeg") else {
                throw EngramError.invalid("Choose a readable image smaller than 10 MB.")
            }
        }
    }
}
