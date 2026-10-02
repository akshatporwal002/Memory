import SwiftUI
import PDFKit
import LearningCore
import DesignSystem
import ImageIO
import UniformTypeIdentifiers
import Vision
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum LibraryDocumentImport {
    static func read(_ url: URL) throws -> LibraryDocument {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let extensionName = url.pathExtension.lowercased()
        guard ["pdf", "md", "markdown", "jpg", "jpeg", "png", "heic"].contains(extensionName) else {
            throw EngramError.invalid("Choose a PDF, Markdown or image file.")
        }
        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent
        if ["jpg", "jpeg", "png", "heic"].contains(extensionName) {
            return try image(data:data,name:(url.deletingPathExtension().lastPathComponent + ".jpg"))
        }
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

    static func image(data: Data, name: String) throws -> LibraryDocument {
        guard data.count <= 40_000_000,
              let source = CGImageSourceCreateWithData(data as CFData,nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:2200
              ] as CFDictionary),
              let context = CGContext(data:nil,width:thumbnail.width,height:thumbnail.height,
                                      bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw EngramError.invalid("Choose a readable image smaller than 40 MB.")
        }
        context.setFillColor(CGColor(gray:1,alpha:1))
        context.fill(CGRect(x:0,y:0,width:thumbnail.width,height:thumbnail.height))
        context.draw(thumbnail,in:CGRect(x:0,y:0,width:thumbnail.width,height:thumbnail.height))
        guard let cgImage = context.makeImage() else { throw EngramError.invalid("The selected image could not be processed.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil) else {
            throw EngramError.invalid("The selected image could not be saved.")
        }
        CGImageDestinationAddImage(destination,cgImage,[kCGImageDestinationLossyCompressionQuality:0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination),output.length <= 10_000_000 else {
            throw EngramError.invalid("This image is too large to save. Choose one under 10 MB after conversion.")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage:cgImage).perform([request])
        let recognized = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator:"\n")
        let pages = recognized.isEmpty ? [] : [PDFPageText(number:1,text:String(recognized.prefix(200_000)))]
        let document = LibraryDocument(name:name,kind:.image,pages:pages,originalData:output as Data)
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
                } else if document.kind == .image {
                    #if os(iOS)
                    if let image = UIImage(data:document.originalData) {
                        ScrollView {
                            Image(uiImage:image).resizable().scaledToFit()
                                .accessibilityLabel(document.name)
                                .frame(maxWidth:720).padding(16).frame(maxWidth:.infinity)
                        }
                    } else { ContentUnavailableView("Image unavailable",systemImage:"photo",description:Text("The saved image could not be opened.")) }
                    #else
                    if let image = NSImage(data:document.originalData) {
                        ScrollView { Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:720).padding(16) }
                    } else { ContentUnavailableView("Image unavailable",systemImage:"photo",description:Text("The saved image could not be opened.")) }
                    #endif
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
