import Foundation

public struct SafeCardStyle: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let bold = SafeCardStyle(rawValue: 1 << 0)
    public static let italic = SafeCardStyle(rawValue: 1 << 1)
    public static let underline = SafeCardStyle(rawValue: 1 << 2)
    public static let strike = SafeCardStyle(rawValue: 1 << 3)
    public static let monospace = SafeCardStyle(rawValue: 1 << 4)
}
public struct SafeCardRun: Equatable, Sendable {
    public let text: String
    public let style: SafeCardStyle
}
public enum SafeCardBlock: Equatable, Sendable {
    case text([SafeCardRun])
    case image(name: String, alternative: String)
    case audio(name: String)
}
public struct SafeCardDocument: Equatable, Sendable {
    public let blocks: [SafeCardBlock]
    /// Any finding means the field cannot be rendered faithfully by this supported subset.
    public let findings: [String]
    public var isSupported: Bool { findings.isEmpty }
    public var mediaNames: [String] {
        blocks.compactMap { block in
            switch block { case .image(let name, _), .audio(let name): return name; case .text: return nil }
        }
    }
    public var plainText: String {
        blocks.compactMap { block in if case .text(let runs) = block { return runs.map(\.text).joined() }; return nil }.joined(separator: "\n")
    }
}

/// Strict, non-executing imported-card markup subset. No browser, filesystem or network API.
/// Allowed tags: b/strong, i/em, u, s/strike, code/pre, br, p/div/span, img.
/// Only img may have attributes: src and optional alt/title. All CSS, scripts, links,
/// event handlers, unknown tags/attributes, malformed nesting and unsupported entities
/// produce compatibility findings. Text entities are decoded once, never reparsed as HTML.
/// Media accepts validated basenames only: PNG/JPEG/BMP/TIFF/HEIC images and
/// MP3/M4A/AAC/WAV/AIFF/CAF audio. Anki audio syntax is [sound:filename].
public enum SafeCardMarkup {
    public static func inspect(_ source: String) -> SafeCardDocument {
        guard source.utf8.count <= 1_000_000 else {
            return SafeCardDocument(blocks: [], findings: ["Card fields must be 1 MB or smaller."])
        }
        var parser = MarkupParser(source)
        return parser.parse()
    }
}

private struct MarkupParser {
    let characters: [Character]
    var cursor = 0
    var blocks: [SafeCardBlock] = []
    var runs: [SafeCardRun] = []
    var findings: [String] = []
    var stack: [(name: String, style: SafeCardStyle)] = []
    var pendingParagraph = false
    var tokenCount = 0
    init(_ source: String) { characters = Array(source) }
    var currentStyle: SafeCardStyle { stack.reduce([]) { $0.union($1.style) } }

    mutating func parse() -> SafeCardDocument {
        var buffer = ""
        while cursor < characters.count {
            if characters[cursor] == "<", beginsTag(cursor) {
                appendText(decodeEntities(buffer)); buffer = ""
                guard let end = tagEnd(cursor + 1) else { issue("Unterminated HTML tag."); break }
                consumeTag(String(characters[(cursor + 1)..<end]))
                cursor = end + 1; tokenCount += 1
            } else if beginsSound(cursor) {
                appendText(decodeEntities(buffer)); buffer = ""
                guard let end = characters[(cursor + 7)...].firstIndex(of: "]") else { issue("Unterminated [sound:filename] marker."); break }
                let raw = decodeEntities(String(characters[(cursor + 7)..<end]))
                if let name = mediaName(raw, image: false) { flush(); blocks.append(.audio(name: name)) }
                cursor = end + 1; tokenCount += 1
            } else {
                buffer.append(characters[cursor]); cursor += 1
            }
            if tokenCount > 20_000 || stack.count > 256 { issue("Card markup exceeds the supported complexity limit."); break }
        }
        appendText(decodeEntities(buffer)); flush()
        if !stack.isEmpty { issue("Unclosed or mismatched formatting tags.") }
        return SafeCardDocument(blocks: blocks, findings: findings)
    }
    func beginsTag(_ position: Int) -> Bool {
        guard position + 1 < characters.count else { return false }
        let next = characters[position + 1]
        return next.isASCII && (next.isLetter || next == "/" || next == "!" || next == "?")
    }
    func beginsSound(_ position: Int) -> Bool {
        let marker = Array("[sound:")
        guard position + marker.count <= characters.count else { return false }
        return Array(characters[position..<(position + marker.count)]) == marker
    }
    func tagEnd(_ start: Int) -> Int? {
        var quote: Character?
        var position = start
        while position < characters.count {
            let char = characters[position]
            if let active = quote { if char == active { quote = nil } }
            else if char == "'" || char == "\"" { quote = char }
            else if char == ">" { return position }
            position += 1
        }
        return nil
    }
    mutating func consumeTag(_ raw: String) {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let closing = body.hasPrefix("/")
        if closing { body.removeFirst(); body = body.trimmingCharacters(in: .whitespacesAndNewlines) }
        let selfClosing = body.hasSuffix("/")
        if selfClosing { body.removeLast() }
        let name = String(body.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }).lowercased()
        let tail = String(body.dropFirst(name.count))
        let allowed: Set<String> = ["b", "strong", "i", "em", "u", "s", "strike", "code", "pre", "br", "p", "div", "span", "img"]
        guard allowed.contains(name) else { issue("Unsupported HTML tag: \(name.isEmpty ? "declaration" : name). No imported code is executed."); return }
        if closing {
            guard tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !selfClosing,
                  stack.last?.name == name else { issue("Unclosed or mismatched formatting tags."); return }
            stack.removeLast()
            if ["p", "div", "pre"].contains(name) { paragraphBreak() }
            return
        }
        let attributes = parseAttributes(tail)
        if name == "img" {
            guard Set(attributes.keys).isSubset(of: ["src", "alt", "title"]), let source = attributes["src"] else {
                issue("Images require a local src and support only alt/title text attributes."); return
            }
            if let filename = mediaName(source, image: true) {
                flush(); blocks.append(.image(name: filename, alternative: attributes["alt"] ?? attributes["title"] ?? filename))
            }
            return
        }
        guard attributes.isEmpty else { issue("Attributes and custom styles are not supported on <\(name)>."); return }
        if name == "br" { appendText("\n"); return }
        guard !selfClosing else { issue("Only br and img may be self-closing."); return }
        if ["p", "div", "pre"].contains(name) { paragraphBreak() }
        let style: SafeCardStyle
        switch name {
        case "b", "strong": style = .bold
        case "i", "em": style = .italic
        case "u": style = .underline
        case "s", "strike": style = .strike
        case "pre", "code": style = .monospace
        default: style = []
        }
        stack.append((name, style))
    }
    mutating func parseAttributes(_ source: String) -> [String: String] {
        let input = Array(source)
        var index = 0
        var result: [String: String] = [:]
        while index < input.count {
            while index < input.count && input[index].isWhitespace { index += 1 }
            if index == input.count { break }
            let start = index
            while index < input.count && input[index].isASCII && (input[index].isLetter || input[index].isNumber || input[index] == "-" || input[index] == "_") { index += 1 }
            guard start != index else { issue("Malformed HTML attributes."); return result }
            let name = String(input[start..<index]).lowercased()
            while index < input.count && input[index].isWhitespace { index += 1 }
            guard index < input.count && input[index] == "=" else { issue("Unsupported boolean or malformed HTML attribute: \(name)."); return result }
            index += 1
            while index < input.count && input[index].isWhitespace { index += 1 }
            guard index < input.count else { issue("Missing HTML attribute value."); return result }
            let value: String
            if input[index] == "'" || input[index] == "\"" {
                let quote = input[index]; index += 1
                let valueStart = index
                while index < input.count && input[index] != quote { index += 1 }
                guard index < input.count else { issue("Unterminated HTML attribute."); return result }
                value = String(input[valueStart..<index]); index += 1
            } else {
                let valueStart = index
                while index < input.count && !input[index].isWhitespace { index += 1 }
                value = String(input[valueStart..<index])
            }
            guard result[name] == nil else { issue("Duplicate HTML attribute: \(name)."); return result }
            result[name] = decodeEntities(value)
            if index < input.count && !input[index].isWhitespace { issue("HTML attributes require whitespace separators."); return result }
        }
        return result
    }
    mutating func mediaName(_ raw: String, image: Bool) -> String? {
        let name = raw.removingPercentEncoding ?? raw
        do { try LibraryValidation.validateMediaName(name) }
        catch { issue("Media references must be local filenames without paths or URL schemes."); return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        let supported = image ? ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "heic", "heif"] : ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf"]
        guard supported.contains(ext) else { issue("Unsupported \(image ? "image" : "audio") format: \(ext.isEmpty ? "no extension" : ext)."); return nil }
        return name
    }
    mutating func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        if pendingParagraph {
            pendingParagraph = false
            if !runs.isEmpty, runs.last?.text.hasSuffix("\n") == false { addRun("\n", style: []) }
        }
        addRun(text, style: currentStyle)
    }
    mutating func addRun(_ text: String, style: SafeCardStyle) {
        if let last = runs.last, last.style == style {
            runs[runs.count - 1] = SafeCardRun(text: last.text + text, style: style)
        } else { runs.append(SafeCardRun(text: text, style: style)) }
    }
    mutating func paragraphBreak() { if !runs.isEmpty { pendingParagraph = true } }
    mutating func flush() {
        if !runs.isEmpty { blocks.append(.text(runs)); runs.removeAll(keepingCapacity: true) }
        pendingParagraph = false
    }
    mutating func issue(_ text: String) {
        if findings.count < 32 && !findings.contains(text) { findings.append(text) }
    }
    mutating func decodeEntities(_ source: String) -> String {
        guard source.contains("&") else { return source }
        let names = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00a0}",
                     "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "reg": "®", "deg": "°",
                     "times": "×", "divide": "÷", "plusmn": "±", "le": "≤", "ge": "≥", "ne": "≠"]
        let input = Array(source)
        var result = ""
        var index = 0
        while index < input.count {
            guard input[index] == "&" else { result.append(input[index]); index += 1; continue }
            var end = index + 1
            while end < input.count && end - index <= 32 && input[end] != ";" && !input[end].isWhitespace && input[end] != "&" { end += 1 }
            guard end < input.count && input[end] == ";" else { result.append("&"); index += 1; continue }
            let name = String(input[(index + 1)..<end])
            var decoded = names[name]
            if name.hasPrefix("#") {
                let hexadecimal = name.lowercased().hasPrefix("#x")
                if let number = UInt32(name.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
                   let scalar = UnicodeScalar(number), number != 0 { decoded = String(scalar) }
            }
            if let decoded { result += decoded }
            else { issue("Unsupported HTML entity: &\(name);."); result += String(input[index...end]) }
            index = end + 1
        }
        return result
    }
}
