import SwiftUI
import PDFKit
import LearningCore
import DesignSystem

enum LibraryDocumentImport {
    static func read(_ url: URL) throws -> LibraryDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let extensionName = url.pathExtension.lowercased()
        guard ["pdf", "md", "markdown"].contains(extensionName) else {
            throw EngramError.invalid("Choose a PDF or Markdown file.")
        }
        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent
        if extensionName == "pdf" {
            guard data.count <= 25_000_000, data.starts(with: Data("%PDF-".utf8)),
                  let pdf = PDFDocument(data: data), !pdf.isLocked, (1...300).contains(pdf.pageCount) else {
                throw EngramError.invalid("Choose an unlocked PDF smaller than 25 MB and 300 pages.")
            }
            var pages: [PDFPageText] = [], count = 0
            for index in 0..<pdf.pageCount {
                let text = pdf.page(at: index)?.string ?? ""
                count += text.utf8.count
                guard count <= 2_000_000 else { throw EngramError.invalid("The PDF has more than 2 MB of extracted text.") }
                pages.append(PDFPageText(number: index + 1, text: text))
            }
            let document = LibraryDocument(name: name, kind: .pdf, pages: pages, originalData: data)
            try document.validate()
            return document
        }
        guard data.count <= 2_000_000, let text = String(data: data, encoding: .utf8) else {
            throw EngramError.invalid("Choose a UTF-8 Markdown file smaller than 2 MB.")
        }
        let document = LibraryDocument(name: name, kind: .markdown,
                                       pages: [PDFPageText(number: 1, text: text)], originalData: data)
        try document.validate()
        return document
    }
}

struct LibraryDocumentReader: View {
    let document: LibraryDocument
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if document.kind == .pdf {
                    if PDFDocument(data: document.originalData) != nil {
                        NativePDFReader(data: document.originalData)
                    } else { ContentUnavailableView("PDF unavailable", systemImage: "doc.text", description: Text("The saved file could not be opened.")) }
                } else {
                    ScrollView {
                        RichContentView(source: document.pages.first?.text ?? "")
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(20).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(document.name).engramInlineTitle().engramCanvas()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct NativePDFReader {
    let data: Data
    func configure(_ view: PDFView) {
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(data:data)
    }
}
#if os(iOS)
extension NativePDFReader: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#else
extension NativePDFReader: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#endif
