import Foundation

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
        case .matrix: return "2 × 2 matrix"; case .vector: return "Vector"
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
    private indirect enum Node: Equatable, Sendable {
        case text(UUID, String)
        case template(MathEntryTemplate, [[Node]])
        var depth: Int { switch self { case .text: return 1; case .template(_, let arguments): return 1 + (arguments.flatMap { $0 }.map(\.depth).max() ?? 0) } }
    }
    private var nodes: [Node]
    public init() { nodes = [.text(UUID(), "")] }
    public var slots: [Slot] { Self.slots(nodes, label: "Expression") }
    public var complete: Bool { slots.allSatisfy { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public var latex: String { Self.render(nodes) }
    @discardableResult public mutating func update(id: UUID, value: String) -> Bool {
        guard value.utf8.count <= 2_000 else { return false }
        var candidate = nodes
        let changed = Self.replace(&candidate, id: id) { _ in [.text(id, value)] }
        guard changed, Self.render(candidate).utf8.count <= 12_000 else { return false }
        nodes = candidate; return true
    }
    /// Nested insertion retains both sides of the selected character offset. The
    /// default is the end of a slot; positions use graphemes, not UTF-16 indices.
    public mutating func insert(_ template: MathEntryTemplate, at id: UUID, offset: Int? = nil) -> UUID? {
        guard slots.count + template.labels.count + 1 <= 100, (nodes.map(\.depth).max() ?? 0) < 12 else { return nil }
        let arguments = template.labels.map { _ in [Node.text(UUID(), "")] }
        guard case .text(let first, _) = arguments[0][0] else { return nil }
        var candidate = nodes
        let changed = Self.replace(&candidate, id: id) { value in
            let point = value.index(value.startIndex, offsetBy: max(0, min(offset ?? value.count, value.count)))
            var result: [Node] = []
            if point != value.startIndex { result.append(.text(id, String(value[..<point]))) }
            result.append(.template(template, arguments))
            if point != value.endIndex { result.append(.text(UUID(), String(value[point...]))) }
            return result
        }
        guard changed, Self.render(candidate).utf8.count <= 12_000 else { return nil }
        nodes = candidate; return first
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
            case .template(let template, let arguments):
                return arguments.enumerated().flatMap { index, argument in slots(argument, label: template.title + " · " + template.labels[index]) }
            }
        }
    }
    private static func render(_ values: [Node]) -> String {
        values.map { node in
            switch node {
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
