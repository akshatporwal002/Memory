import Foundation

/// Ephemeral native selection, tied to its exact field value. Not library data.
public struct MathEntryTextSelection: Equatable {
    public let source: String
    public let utf16Range: NSRange
    public init?(source: String, utf16Range: NSRange) {
        guard source.utf8.count <= 2_000, let range = Range(utf16Range, in: source),
              range.lowerBound == source.endIndex || source.indices.contains(range.lowerBound),
              range.upperBound == source.endIndex || source.indices.contains(range.upperBound) else { return nil }
        self.source = source; self.utf16Range = utf16Range
    }
    var offsets: (Int, Int) {
        let range = Range(utf16Range, in: source)!
        return (source.distance(from: source.startIndex, to: range.lowerBound), source.distance(from: range.lowerBound, to: range.upperBound))
    }
}

public enum MathEntryCategory: String, CaseIterable, Hashable, Sendable {
    case arithmetic = "Basics", algebra = "Algebra", functions = "Functions", calculus = "Calculus"
    case linear = "Matrices", sets = "Sets", probability = "Probability", greek = "Greek"
}
public enum MathEntryTemplate: String, CaseIterable, Hashable, Sendable {
    case fraction, power, root, nthRoot, parentheses, brackets, absolute, lessEqual, greaterEqual
    case sine, cosine, tangent, logarithm, naturalLog, exponential
    case derivative, partialDerivative, integral, definiteIntegral, limit, sum, product
    case matrix, vector, piecewise, set, union, intersection, membership
    case factorial, permutation, combination, probability, conditionalProbability, binomial, normal, poisson
    public var category: MathEntryCategory {
        switch self {
        case .fraction, .power, .root, .nthRoot, .parentheses, .brackets, .absolute: return .arithmetic
        case .lessEqual, .greaterEqual: return .algebra
        case .sine, .cosine, .tangent, .logarithm, .naturalLog, .exponential: return .functions
        case .derivative, .partialDerivative, .integral, .definiteIntegral, .limit, .sum, .product: return .calculus
        case .matrix, .vector: return .linear
        case .piecewise, .set, .union, .intersection, .membership: return .sets
        default: return .probability
        }
    }
    public var title: String {
        switch self {
        case .fraction: return "Fraction"; case .power: return "Power"; case .root: return "√"
        case .nthRoot: return "Nth root"; case .parentheses: return "( )"; case .brackets: return "[ ]"; case .absolute: return "|x|"
        case .lessEqual: return "≤"; case .greaterEqual: return "≥"
        case .sine: return "sin"; case .cosine: return "cos"; case .tangent: return "tan"
        case .logarithm: return "log"; case .naturalLog: return "ln"; case .exponential: return "eˣ"
        case .derivative: return "Derivative"; case .partialDerivative: return "Partial ∂"
        case .integral: return "∫"; case .definiteIntegral: return "Definite ∫"; case .limit: return "Limit"
        case .sum: return "Σ"; case .product: return "Product Π"
        case .matrix: return "Matrix"; case .vector: return "Vector"
        case .piecewise: return "Piecewise"; case .set: return "Set { }"; case .union: return "Union ∪"
        case .intersection: return "Intersection ∩"; case .membership: return "Member ∈"
        case .factorial: return "n!"; case .permutation: return "nPr"; case .combination: return "nCr"
        case .probability: return "P(A)"; case .conditionalProbability: return "P(A | B)"
        case .binomial: return "Binomial"; case .normal: return "Normal"; case .poisson: return "Poisson"
        }
    }
    public var labels: [String] {
        switch self {
        case .fraction: return ["Numerator", "Denominator"]
        case .power: return ["Base", "Exponent"]
        case .root, .parentheses, .brackets, .absolute: return ["Expression"]
        case .nthRoot: return ["Index", "Radicand"]
        case .lessEqual, .greaterEqual, .union, .intersection: return ["Left", "Right"]
        case .sine, .cosine, .tangent, .naturalLog: return ["Argument"]
        case .logarithm: return ["Base", "Argument"]
        case .exponential: return ["Exponent"]
        case .derivative, .partialDerivative: return ["Function", "Variable"]
        case .integral: return ["Integrand", "Variable"]
        case .definiteIntegral: return ["Lower bound", "Upper bound", "Integrand", "Variable"]
        case .limit: return ["Variable", "Approaches", "Expression"]
        case .sum, .product: return ["Index", "Starts at", "Ends at", "Term"]
        case .matrix: return ["Row 1 column 1", "Row 1 column 2", "Row 2 column 1", "Row 2 column 2"]
        case .vector: return ["Vector name"]
        case .piecewise: return ["First expression", "First condition", "Second expression", "Second condition"]
        case .set: return ["Elements"]
        case .membership: return ["Element", "Set"]
        case .factorial: return ["Number"]
        case .permutation, .combination: return ["n", "r"]
        case .probability: return ["Event"]
        case .conditionalProbability: return ["Event", "Given"]
        case .binomial: return ["Variable", "Trials n", "Success probability p"]
        case .normal: return ["Variable", "Mean μ", "Variance σ²"]
        case .poisson: return ["Variable", "Rate λ"]
        }
    }
    fileprivate var pattern: String {
        switch self {
        case .fraction: return #"\frac{«0»}{«1»}"#
        case .power: return #"{«0»}^{«1»}"#
        case .root: return #"\sqrt{«0»}"#
        case .nthRoot: return #"\sqrt[«0»]{«1»}"#
        case .parentheses: return #"\left(«0»\right)"#
        case .brackets: return #"\left[«0»\right]"#
        case .absolute: return #"\left|«0»\right|"#
        case .lessEqual: return #"«0»\leq «1»"#
        case .greaterEqual: return #"«0»\geq «1»"#
        case .sine: return #"\sin\left(«0»\right)"#
        case .cosine: return #"\cos\left(«0»\right)"#
        case .tangent: return #"\tan\left(«0»\right)"#
        case .logarithm: return #"\log_{«0»}\left(«1»\right)"#
        case .naturalLog: return #"\ln\left(«0»\right)"#
        case .exponential: return #"e^{«0»}"#
        case .derivative: return #"\frac{d}{d«1»}\left(«0»\right)"#
        case .partialDerivative: return #"\frac{\partial}{\partial «1»}\left(«0»\right)"#
        case .integral: return #"\int «0»\,d«1»"#
        case .definiteIntegral: return #"\int_{«0»}^{«1»}«2»\,d«3»"#
        case .limit: return #"\lim_{«0»\to «1»}«2»"#
        case .sum: return #"\sum_{«0»=«1»}^{«2»}«3»"#
        case .product: return #"\prod_{«0»=«1»}^{«2»}«3»"#
        case .matrix: return #"\begin{pmatrix}«0»&«1»\\«2»&«3»\end{pmatrix}"#
        case .vector: return #"\vec{«0»}"#
        case .piecewise: return #"\begin{cases}«0»&«1»\\«2»&«3»\end{cases}"#
        case .set: return #"\left\{«0»\right\}"#
        case .union: return #"«0»\cup «1»"#
        case .intersection: return #"«0»\cap «1»"#
        case .membership: return #"«0»\in «1»"#
        case .factorial: return #"\left(«0»\right)!"#
        case .permutation: return #"{}_{«0»}P_{«1»}"#
        case .combination: return #"\binom{«0»}{«1»}"#
        case .probability: return #"P\left(«0»\right)"#
        case .conditionalProbability: return #"P\left(«0»\mid «1»\right)"#
        case .binomial: return #"«0»\sim\operatorname{Bin}\left(«1»,«2»\right)"#
        case .normal: return #"«0»\sim\mathcal{N}\left(«1»,«2»\right)"#
        case .poisson: return #"«0»\sim\operatorname{Poisson}\left(«1»\right)"#
        }
    }
}

public struct MathEntryDocument: Equatable, Sendable {
    public struct Slot: Identifiable, Equatable, Sendable { public let id: UUID; public let label: String; public let value: String }
    public struct Dimensions: Equatable, Sendable {
        public let kind: MathEntryTemplate
        public let rows: Int
        public let columns: Int
    }
    private struct Definition: Equatable, Sendable {
        let kind: MathEntryTemplate
        let labels: [String]
        let pattern: String
        let dimensions: Dimensions?
        init(kind: MathEntryTemplate, labels: [String], pattern: String, dimensions: Dimensions? = nil) {
            self.kind = kind; self.labels = labels; self.pattern = pattern
            self.dimensions = dimensions ?? (kind == .matrix ? Dimensions(kind: kind, rows: 2, columns: 2) : kind == .piecewise ? Dimensions(kind: kind, rows: 2, columns: 2) : nil)
        }
        var title: String { kind.title }
    }
    private indirect enum Node: Equatable, Sendable {
        case text(UUID, String)
        case separator
        case template(Definition, [[Node]])
        var depth: Int { switch self { case .text, .separator: return 1; case .template(_, let arguments): return 1 + (arguments.flatMap { $0 }.map(\.depth).max() ?? 0) } }
    }
    private var nodes: [Node]
    private var undoStates: [[Node]] = []
    private var redoStates: [[Node]] = []
    public init() { nodes = [.text(UUID(), "")] }
    public var slots: [Slot] { Self.slots(nodes, label: "Expression") }
    public var complete: Bool { slots.allSatisfy { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public var latex: String { Self.render(nodes) }
    public var canUndo: Bool { !undoStates.isEmpty }
    public var canRedo: Bool { !redoStates.isEmpty }
    /// Continue outside the completed template, e.g. a fraction followed by +x.
    public mutating func appendExpression() -> UUID? {
        guard slots.count < 100, latex.utf8.count < 12_000 else { return nil }
        let id = UUID(); var candidate = nodes; candidate.append(.text(id, "")); accept(candidate); return id
    }
    public mutating func undo() {
        guard let previous = undoStates.popLast() else { return }
        redoStates.append(nodes); nodes = previous
    }
    public mutating func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(nodes); nodes = next
    }
    private mutating func accept(_ candidate: [Node]) {
        guard candidate != nodes else { return }
        undoStates.append(nodes)
        if undoStates.count > 50 { undoStates.removeFirst(undoStates.count - 50) }
        redoStates = []; nodes = candidate
    }
    @discardableResult public mutating func update(id: UUID, value: String) -> Bool {
        guard value.utf8.count <= 2_000 else { return false }
        var candidate = nodes
        let changed = Self.replace(&candidate, id: id) { _ in [.text(id, value)] }
        guard changed, Self.render(candidate).utf8.count <= 12_000 else { return false }
        accept(candidate); return true
    }
    /// Nested insertion retains both sides of the selected character offset. The
    /// default is the end of a slot; positions use graphemes, not UTF-16 indices.
    public mutating func insert(_ template: MathEntryTemplate, at id: UUID, offset: Int? = nil) -> UUID? {
        if template == .matrix { return insert(Self.matrixDefinition(rows: 2, columns: 2), at: id, offset: offset) }
        if template == .piecewise { return insert(Self.piecewiseDefinition(cases: 2), at: id, offset: offset) }
        return insert(Definition(kind: template, labels: template.labels, pattern: template.pattern), at: id, offset: offset)
    }
    public mutating func insert(_ template: MathEntryTemplate, at id: UUID, selection: MathEntryTextSelection) -> UUID? {
        guard slots.first(where: { $0.id == id })?.value == selection.source else { return nil }
        let (offset, length) = selection.offsets
        return insert(Definition(kind: template, labels: template.labels, pattern: template.pattern), at: id, offset: offset, replacingCount: length)
    }
    public mutating func insertMatrix(rows: Int, columns: Int, at id: UUID, selection: MathEntryTextSelection) -> UUID? {
        guard (1...6).contains(rows), (1...6).contains(columns), slots.first(where: { $0.id == id })?.value == selection.source else { return nil }
        let (offset, length) = selection.offsets
        return insert(Self.matrixDefinition(rows: rows, columns: columns), at: id, offset: offset, replacingCount: length)
    }
    public mutating func insertPiecewise(cases: Int, at id: UUID, selection: MathEntryTextSelection) -> UUID? {
        guard (1...6).contains(cases), slots.first(where: { $0.id == id })?.value == selection.source else { return nil }
        let (offset, length) = selection.offsets
        return insert(Self.piecewiseDefinition(cases: cases), at: id, offset: offset, replacingCount: length)
    }
    /// Insert plain notation at the cursor, replacing only selected graphemes.
    /// A stale selection rejects the edit rather than touching different text.
    public mutating func replaceText(_ text: String, at id: UUID, selection: MathEntryTextSelection? = nil) -> MathEntryTextSelection? {
        guard let slot = slots.first(where: { $0.id == id }), text.utf8.count <= 2_000 else { return nil }
        let selected = selection ?? MathEntryTextSelection(source: slot.value, utf16Range: NSRange(location: slot.value.utf16.count, length: 0))!
        guard selected.source == slot.value, let range = Range(selected.utf16Range, in: slot.value) else { return nil }
        let value = String(slot.value[..<range.lowerBound]) + text + String(slot.value[range.upperBound...])
        guard let caret = MathEntryTextSelection(source: value, utf16Range: NSRange(location: selected.utf16Range.location + text.utf16.count, length: 0)), update(id: id, value: value) else { return nil }
        return caret
    }
    public mutating func insertMatrix(rows: Int, columns: Int, at id: UUID, offset: Int? = nil) -> UUID? {
        guard (1...6).contains(rows), (1...6).contains(columns) else { return nil }
        return insert(Self.matrixDefinition(rows: rows, columns: columns), at: id, offset: offset)
    }
    private static func matrixDefinition(rows: Int, columns: Int) -> Definition {
        let labels = (0..<rows).flatMap { row in (0..<columns).map { column in "Row \(row + 1) column \(column + 1)" } }
        let entries = (0..<rows).map { row in (0..<columns).map { column in "«\(row * columns + column)»" }.joined(separator: "&") }.joined(separator: #"\\"#)
        return Definition(kind: .matrix, labels: labels, pattern: #"\begin{pmatrix}"# + entries + #"\end{pmatrix}"#, dimensions: Dimensions(kind: .matrix, rows: rows, columns: columns))
    }
    public mutating func insertPiecewise(cases: Int, at id: UUID, offset: Int? = nil) -> UUID? {
        guard (1...6).contains(cases) else { return nil }
        return insert(Self.piecewiseDefinition(cases: cases), at: id, offset: offset)
    }
    private static func piecewiseDefinition(cases: Int) -> Definition {
        let labels = (1...cases).flatMap { ["Case \($0) expression", "Case \($0) condition"] }
        let entries = (0..<cases).map { "«\($0 * 2)»&«\($0 * 2 + 1)»" }.joined(separator: #"\\"#)
        return Definition(kind: .piecewise, labels: labels, pattern: #"\begin{cases}"# + entries + #"\end{cases}"#, dimensions: Dimensions(kind: .piecewise, rows: cases, columns: 2))
    }
    public func dimensions(containing id: UUID) -> Dimensions? {
        Self.resizable(nodes, id: id)?.0.dimensions
    }
    public func resizeWouldDiscardContent(containing id: UUID, rows: Int, columns: Int) -> Bool {
        guard let (definition, arguments) = Self.resizable(nodes, id: id), let old = definition.dimensions else { return false }
        return arguments.enumerated().contains { index, argument in
            (index / old.columns >= rows || index % old.columns >= columns) && Self.hasContent(argument)
        }
    }
    /// Resize the nearest matrix/cases ancestor. Existing coordinates, nested
    /// expressions and slot identities survive; nonempty removals require consent.
    @discardableResult public mutating func resize(containing id: UUID, rows: Int, columns: Int, allowDiscardingContent: Bool = false) -> Bool {
        guard (1...6).contains(rows), (1...6).contains(columns), let old = dimensions(containing: id),
              old.kind != .piecewise || columns == 2,
              allowDiscardingContent || !resizeWouldDiscardContent(containing: id, rows: rows, columns: columns) else { return false }
        var candidate = nodes
        guard Self.resize(&candidate, id: id, rows: rows, columns: columns),
              Self.slots(candidate, label: "").count <= 100, Self.render(candidate).utf8.count <= 12_000,
              (candidate.map(\.depth).max() ?? 0) <= 12 else { return false }
        accept(candidate); return true
    }
    private static func hasContent(_ values: [Node]) -> Bool {
        values.contains { node in
            switch node {
            case .text(_, let text): return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .separator: return false
            case .template: return true
            }
        }
    }
    private static func resizable(_ values: [Node], id: UUID) -> (Definition, [[Node]])? {
        for node in values {
            guard case .template(let definition, let arguments) = node else { continue }
            for argument in arguments { if let found = resizable(argument, id: id) { return found } }
            if definition.dimensions != nil, arguments.contains(where: { slots($0, label: "").contains { $0.id == id } }) { return (definition, arguments) }
        }
        return nil
    }
    private static func resize(_ values: inout [Node], id: UUID, rows: Int, columns: Int) -> Bool {
        for index in values.indices {
            guard case .template(let definition, var arguments) = values[index] else { continue }
            for ai in arguments.indices {
                if resize(&arguments[ai], id: id, rows: rows, columns: columns) {
                    values[index] = .template(definition, arguments); return true
                }
            }
            guard let old = definition.dimensions,
                  arguments.contains(where: { slots($0, label: "").contains { $0.id == id } }) else { continue }
            let replacement = old.kind == .matrix ? matrixDefinition(rows: rows, columns: columns) : piecewiseDefinition(cases: rows)
            let contents: [[Node]] = (0..<rows).flatMap { row in
                (0..<columns).map { column -> [Node] in
                    if row < old.rows, column < old.columns { return arguments[row * old.columns + column] }
                    return [.text(UUID(), "")]
                }
            }
            values[index] = .template(replacement, contents); return true
        }
        return false
    }
    private mutating func insert(_ template: Definition, at id: UUID, offset: Int?, replacingCount: Int = 0) -> UUID? {
        guard slots.count + template.labels.count + 1 <= 100, (nodes.map(\.depth).max() ?? 0) < 12 else { return nil }
        let arguments = template.labels.map { _ in [Node.text(UUID(), "")] }
        guard case .text(let first, _) = arguments[0][0] else { return nil }
        var candidate = nodes
        let changed = Self.replace(&candidate, id: id) { value in
            let point = value.index(value.startIndex, offsetBy: max(0, min(offset ?? value.count, value.count)))
            let end = value.index(point, offsetBy: replacingCount)
            var result: [Node] = []
            if point != value.startIndex { result.append(.text(id, String(value[..<point]))) }
            result.append(.template(template, arguments))
            if end != value.endIndex { result.append(.text(UUID(), String(value[end...]))) }
            return result
        }
        guard changed, Self.render(candidate).utf8.count <= 12_000 else { return nil }
        accept(candidate); return first
    }
    public func canRemoveTemplate(containing id: UUID) -> Bool {
        Self.containsTemplate(nodes, id: id)
    }
    /// Unwrap the nearest template containing this slot, preserving argument
    /// contents and their IDs instead of silently deleting the entered values.
    @discardableResult public mutating func removeTemplate(containing id: UUID) -> Bool {
        var candidate = nodes
        guard Self.unwrap(&candidate, id: id), Self.render(candidate).utf8.count <= 12_000 else { return false }
        accept(candidate); return true
    }
    private static func containsTemplate(_ values: [Node], id: UUID) -> Bool {
        values.contains { node in
            if case .template(_, let arguments) = node { return arguments.contains { slots($0, label: "").contains { $0.id == id } } }
            return false
        }
    }
    private static func unwrap(_ values: inout [Node], id: UUID) -> Bool {
        for index in values.indices {
            guard case .template(let definition, var arguments) = values[index] else { continue }
            for argument in arguments.indices {
                if unwrap(&arguments[argument], id: id) {
                    values[index] = .template(definition, arguments); return true
                }
            }
            if arguments.contains(where: { argument in argument.contains { if case .text(let found, _) = $0 { return found == id }; return false } }) {
                let unwrapped = arguments.enumerated().flatMap { index, argument in index == 0 ? argument : [.separator] + argument }
                values.replaceSubrange(index...index, with: unwrapped); return true
            }
        }
        return false
    }
    private static func replace(_ values: inout [Node], id: UUID, transform: (String) -> [Node]) -> Bool {
        for index in values.indices {
            switch values[index] {
            case .text(let found, let value) where found == id:
                values.replaceSubrange(index...index, with: transform(value)); return true
            case .template(let template, var arguments):
                for argument in arguments.indices where replace(&arguments[argument], id: id, transform: transform) {
                    values[index] = .template(template, arguments); return true
                }
            default: break
            }
        }
        return false
    }
    private static func slots(_ values: [Node], label: String) -> [Slot] {
        values.flatMap { node in
            switch node {
            case .text(let id, let value): return [Slot(id: id, label: label, value: value)]
            case .separator: return []
            case .template(let template, let arguments):
                return arguments.enumerated().flatMap { index, argument in slots(argument, label: template.title + " · " + template.labels[index]) }
            }
        }
    }
    private static func render(_ values: [Node]) -> String {
        values.map { node in
            switch node {
            case .separator: return #"\;"#
            case .text(_, let value):
                if value.isEmpty { return #"\square"# }
                return value.map { character -> String in
                    switch character {
                    case "\\": return #"\backslash{}"#
                    case "{", "}", "$", "%", "#", "&", "_": return "\\" + String(character)
                    case "\n", "\r": return " "
                    default: return String(character)
                    }
                }.joined()
            case .template(let template, let arguments):
                // Parse markers in the trusted recipe, never in inserted values.
                let pieces = template.pattern.components(separatedBy: "«")
                return pieces[0] + pieces.dropFirst().map { piece in
                    guard let end = piece.firstIndex(of: "»"), let index = Int(piece[..<end]), arguments.indices.contains(index) else { return piece }
                    return render(arguments[index]) + String(piece[piece.index(after: end)...])
                }.joined()
            }
        }.joined()
    }
}
