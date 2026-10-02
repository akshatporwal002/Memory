import SwiftUI
import Markdown
import DesignSystem
import WebKit

/// Shared reading surface. Source remains Markdown; raw HTML is never executed.
struct RichContentView: View {
    let source: String
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownCache.document(source).children.enumerated()), id: \.offset) { _, block in
                RichMarkdownBlock(block: block)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.palette(for: scheme).primaryText)
    }
}

@MainActor private enum MarkdownCache {
    private final class Box: NSObject { let document: Document; init(_ source: String) { document = Document(parsing:source) } }
    private static let cache: NSCache<NSString,Box> = { let cache = NSCache<NSString,Box>(); cache.countLimit = 128; cache.totalCostLimit = 2_000_000; return cache }()
    static func document(_ source: String) -> Document {
        if let value = cache.object(forKey:source as NSString) { return value.document }
        let value = Box(source); cache.setObject(value,forKey:source as NSString,cost:source.utf8.count); return value.document
    }
}

private struct RichMarkdownBlock: View {
    let block: any Markup
    @Environment(\.engramTheme) private var theme
    @ViewBuilder var body: some View {
        if let heading = block as? Heading {
            inline(heading).font(heading.level <= 2 ? .title2.weight(.semibold) : .headline)
                .accessibilityAddTraits(.isHeader)
        } else if let code = block as? CodeBlock {
            if code.language == "mermaid" { RichFormulaView(kind: "mermaid", source: code.code) }
            else if code.language == "math" || code.language == "latex" { RichFormulaView(kind: "displayMath", source: code.code) }
            else { ScrollView(.horizontal) { SwiftUI.Text(verbatim: code.code).font(.system(.body, design: .monospaced)).textSelection(.enabled) }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8)) }
        } else if let list = block as? UnorderedList {
            listItems(list, ordered: false)
        } else if let list = block as? OrderedList {
            listItems(list, ordered: true)
        } else if let quote = block as? BlockQuote {
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(.secondary).frame(width: 2)
                children(quote)
            }.fixedSize(horizontal: false, vertical: true)
        } else if block is ThematicBreak { Divider() }
        else if let table = block as? Markdown.Table {
            ScrollView(.horizontal) { VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 16) { ForEach(Array(table.head.children.enumerated()), id: \.offset) { _, cell in inline(cell).bold().frame(width: 150, alignment: .leading) } }
                Divider()
                ForEach(Array(table.body.children.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 16) { ForEach(Array(row.children.enumerated()), id: \.offset) { _, cell in inline(cell).frame(width: 150, alignment: .leading) } }
                }
            }}
        } else if let paragraph = block as? Paragraph {
            let raw = paragraph.format().trimmingCharacters(in: .whitespacesAndNewlines)
            if raw.hasPrefix("$$"), raw.hasSuffix("$$"), raw.count >= 4 {
                RichFormulaView(kind: "displayMath", source: String(raw.dropFirst(2).dropLast(2)))
            } else if raw.contains("\\(") || raw.contains("$") {
                // Math-bearing paragraphs use the same bounded offline renderer.
                RichFormulaView(kind: "richParagraph", source: safeInlineHTML(paragraph))
            } else { inline(paragraph).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
        } else if block is HTMLBlock {
            SwiftUI.Text(verbatim: block.format()).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        } else { inline(block).textSelection(.enabled) }
    }
    private func children(_ markup: any Markup) -> some View {
        VStack(alignment: .leading, spacing: 8) { ForEach(Array(markup.children.enumerated()), id: \.offset) { _, child in RichMarkdownBlock(block: child) } }
    }
    private func listItems(_ markup: any Markup, ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) { ForEach(Array(markup.children.enumerated()), id: \.offset) { index, child in
            HStack(alignment: .top, spacing: 8) { SwiftUI.Text(ordered ? "\(index + 1)." : "•"); children(child) }
        }}
    }
    private func inline(_ markup: any Markup) -> SwiftUI.Text {
        if let text = markup as? Markdown.Text { return SwiftUI.Text(verbatim: text.string) }
        if let code = markup as? InlineCode { return SwiftUI.Text(verbatim: code.code).monospaced() }
        if markup is SoftBreak { return SwiftUI.Text(" ") }
        if markup is LineBreak { return SwiftUI.Text("\n") }
        let result = markup.children.reduce(SwiftUI.Text("")) { $0 + inline($1) }
        if markup is Strong { return result.bold() }
        if markup is Emphasis { return result.italic() }
        if markup is Strikethrough { return result.strikethrough() }
        if let link = markup as? Markdown.Link, let url = link.destination.flatMap(URL.init(string:)), ["https","http"].contains(url.scheme?.lowercased() ?? "") {
            var text = AttributedString((link as? PlainTextConvertibleMarkup)?.plainText ?? link.destination ?? "Link")
            text.link = url
            return SwiftUI.Text(text)
        }
        if let image = markup as? Markdown.Image { return SwiftUI.Text(image.plainText).italic() }
        return result
    }
    private func safeInlineHTML(_ markup: any Markup) -> String {
        func escape(_ text: String) -> String { text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;") }
        if let text = markup as? Markdown.Text { return escape(text.string) }
        if let code = markup as? InlineCode { return "<code>" + escape(code.code) + "</code>" }
        if markup is SoftBreak { return " " }; if markup is LineBreak { return "<br>" }
        let children = markup.children.map { safeInlineHTML($0) }.joined()
        if markup is Strong { return "<strong>" + children + "</strong>" }
        if markup is Emphasis { return "<em>" + children + "</em>" }
        if markup is Strikethrough { return "<s>" + children + "</s>" }
        return children
    }
}

private struct RichFormulaView: View {
    let kind: String
    let source: String
    @Environment(\.colorScheme) private var scheme
    @State private var height: CGFloat = 64
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0
    var body: some View {
        FormulaWebView(kind: kind, source: source, dark: scheme == .dark, fontSize: fontSize, height: $height)
            .frame(height: height).accessibilityLabel(kind == "mermaid" ? "Diagram: \(source)" : "Mathematical content: \(source)")
    }
}

private struct FormulaWebView {
    let kind: String
    let source: String
    let dark: Bool
    let fontSize: Double
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func create(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(coordinator, name: "height")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = coordinator
        #if os(iOS)
        view.isOpaque = false; view.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        #endif
        return view
    }
    func update(_ view: WKWebView, coordinator: Coordinator) {
        let key = "\(kind):\(dark):\(fontSize):\(source)"
        guard key != coordinator.key else { return }; coordinator.key = key
        guard source.utf8.count <= 30_000, let script = Bundle.module.url(forResource: "render", withExtension: "js", subdirectory: "RichContent"),
              let css = Bundle.module.url(forResource: "katex", withExtension: "css", subdirectory: "RichContent"),
              let js = try? String(contentsOf: script, encoding: .utf8), var styles = try? String(contentsOf: css, encoding: .utf8) else {
            view.loadHTMLString("<pre>\(escape(source))</pre>", baseURL: nil); return
        }
        if let fonts = try? FileManager.default.contentsOfDirectory(at: script.deletingLastPathComponent().appendingPathComponent("fonts"), includingPropertiesForKeys: nil) {
            for font in fonts where font.pathExtension == "woff2" {
                if let bytes = try? Data(contentsOf: font) {
                    styles = styles.replacingOccurrences(of: "fonts/" + font.lastPathComponent, with: "data:font/woff2;base64," + bytes.base64EncodedString())
                }
            }
        }
        let safeScript = js.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)
        let args = (try? JSONSerialization.data(withJSONObject: [kind,source,dark] as [Any])).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let safeArgs = args.replacingOccurrences(of: "<", with: "\\u003c").replacingOccurrences(of: ">", with: "\\u003e")
        let html = """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; img-src data:; connect-src 'none'">
        <style>\(styles) body{margin:0;background:transparent;color:\(dark ? "#eee" : "#222");font:\(fontSize)px -apple-system}#content{padding:8px 0;overflow:auto}svg{max-width:100%;height:auto}</style>
        <div id="content"><pre>\(escape(source))</pre></div><script>\(safeScript)</script><script>engramRender(...\(safeArgs));</script>
        """
        view.loadHTMLString(html, baseURL: nil)
    }
    private func escape(_ text: String) -> String { text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var key = ""
        var height: Binding<CGFloat>
        init(height: Binding<CGFloat>) { self.height = height }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            DispatchQueue.main.async { self.height.wrappedValue = max(36,min(2000,number.doubleValue)) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
        }
    }
}
#if os(iOS)
extension FormulaWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { create(context.coordinator) }
    func updateUIView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#else
extension FormulaWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { create(context.coordinator) }
    func updateNSView(_ view: WKWebView, context: Context) { update(view, coordinator: context.coordinator) }
}
#endif
