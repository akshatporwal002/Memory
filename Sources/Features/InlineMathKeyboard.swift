import SwiftUI
import LearningCore
import DesignSystem

/// Inline notation entry. Keys change faces with modifiers; no system keyboard,
/// calculator evaluation or separate editor page is involved.
struct InlineMathKeyboard: View {
    @Binding var answer: String
    let advanced: Bool
    @Binding var document: MathEntryDocument
    @State private var selected: UUID?
    @State private var modifier = Modifier.base
    @State private var alphabet = false
    @State private var error: String?
    @State private var cursor = 0
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private enum Modifier { case base, control, shift }
    private struct Key: Identifiable {
        let id: String
        let title: String
        var symbol: String? = nil
        var template: MathEntryTemplate? = nil
        var insertion: String? = nil
    }
    private var numericKeys: [Key] {
        let first: [Key]
        let second: [Key]
        let third: [Key]
        switch modifier {
        case .base:
            first = [Key(id: "equals", title: "=", insertion: "="), Key(id: "trig", title: "sin", template: .sine)]
            second = [Key(id: "power", title: "xⁿ", template: .power), Key(id: "square", title: "x²", insertion: "²")]
            third = [Key(id: "exp", title: "eˣ", template: .exponential), Key(id: "log", title: "log", template: .logarithm)]
        case .control:
            first = [Key(id: "equals", title: "≤", template: .lessEqual), Key(id: "trig", title: "cos", template: .cosine)]
            second = [Key(id: "power", title: "ⁿ√", template: .nthRoot), Key(id: "square", title: "√", template: .root)]
            third = [Key(id: "exp", title: "ln", template: .naturalLog), Key(id: "log", title: "nCr", template: .combination)]
        case .shift:
            first = [Key(id: "equals", title: "≥", template: .greaterEqual), Key(id: "trig", title: "tan", template: .tangent)]
            second = [Key(id: "power", title: "∫", template: .integral), Key(id: "square", title: "∑", template: .sum)]
            third = [Key(id: "exp", title: "d/dx", template: .derivative), Key(id: "log", title: "P( )", template: .probability)]
        }
        func digits(_ values: [String]) -> [Key] { values.map { Key(id: $0, title: $0, insertion: $0) } }
        return first + digits(["7", "8", "9"]) + [Key(id: "absolute", title: modifier == .base ? "|x|" : "{ }", template: modifier == .base ? .absolute : .set), Key(id: "fraction", title: "▱", template: .fraction)]
            + second + digits(["4", "5", "6"]) + digits(["×", "÷"])
            + third + digits(["1", "2", "3"]) + digits(["+", "−"])
            + [Key(id: "left", title: "(", insertion: "("), Key(id: "right", title: ")", insertion: ")")] + digits(["0", ".", "π"])
            + [Key(id: "negative", title: "(−)", insertion: "−"), Key(id: "next", title: "Next", symbol: "arrow.right.to.line")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                RichContentView(source: "$$\n" + document.latex + "\n$$")
                    .frame(maxWidth: .infinity, minHeight: 80).accessibilityLabel("Your mathematical response")
            }.frame(height: 100)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    ForEach(Array(document.slots.enumerated()), id: \.element.id) { index, slot in
                        Button {
                            selected = slot.id; cursor = slot.value.count
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slot.label).font(.caption2).foregroundStyle(palette.secondaryText)
                                Text(display(slot)).font(.body).lineLimit(1)
                                    .foregroundStyle(slot.id == (selected ?? document.slots.first?.id) ? palette.accentInk : palette.primaryText)
                                Rectangle().fill(slot.id == (selected ?? document.slots.first?.id) ? palette.accentInk : palette.hairline).frame(height: 1)
                            }.frame(minWidth: 44, minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("Edit " + slot.label).accessibilityValue(slot.value)
                            .accessibilityIdentifier("math-slot-\(index)")
                    }
                }
            }
            HStack(spacing: 0) {
                modifierKey("ctrl", value: .control)
                modifierKey("shift", value: .shift)
                ForEach(["x", "y", "z"], id: \.self) { value in keyButton(Key(id: value, title: value, insertion: value)) }
                keyButton(Key(id: "undo", title: "Undo", symbol: "arrow.uturn.backward"))
                keyButton(Key(id: "delete", title: "Delete", symbol: "delete.left"))
            }
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: alphabet ? 6 : 7), spacing: 0) {
                if alphabet {
                    ForEach(Array("abcdefghijklmnopqrstuvwxyz").map(String.init), id: \.self) { letter in
                        keyButton(Key(id: letter, title: modifier == .shift ? letter.uppercased() : letter, insertion: modifier == .shift ? letter.uppercased() : letter))
                    }
                } else { ForEach(numericKeys) { keyButton($0) } }
            }.accessibilityIdentifier("inline-math-keyboard")
            Divider()
            HStack(spacing: 16) {
                Button(alphabet ? "123" : "ABC") { alphabet.toggle() }.frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(alphabet ? "Show maths keys" : "Show alphabet")
                Button { moveCursor(-1) } label: { Image(systemName: "chevron.left") }.frame(width: 44, height: 44).accessibilityLabel("Move cursor left")
                Button { moveCursor(1) } label: { Image(systemName: "chevron.right") }.frame(width: 44, height: 44).accessibilityLabel("Move cursor right")
                Spacer(minLength: 0)
                if advanced {
                    Menu {
                        ForEach(MathEntryCategory.allCases, id: \.self) { category in
                            Menu(category.rawValue) {
                                ForEach(MathEntryTemplate.allCases.filter { $0.category == category }, id: \.self) { template in
                                    Button(template.title) { insert(template) }
                                }
                                if category == .greek {
                                    ForEach(["α", "β", "γ", "δ", "θ", "λ", "μ", "σ", "ω", "∞"], id: \.self) { value in Button(value) { write(value) } }
                                }
                            }
                        }
                        if let selected, document.canRemoveTemplate(containing: selected) {
                            Button("Remove template, keep values") { _ = document.removeTemplate(containing: selected); normalize() }
                        }
                        if let selected, let dimensions = document.dimensions(containing: selected) {
                            Menu("Size: \(dimensions.rows) × \(dimensions.columns)") {
                                Button("Add row") { resize(selected, rows: dimensions.rows + 1, columns: dimensions.columns) }.disabled(dimensions.rows >= 6)
                                Button("Remove row") { resize(selected, rows: dimensions.rows - 1, columns: dimensions.columns) }.disabled(dimensions.rows <= 1)
                                if dimensions.kind == .matrix {
                                    Button("Add column") { resize(selected, rows: dimensions.rows, columns: dimensions.columns + 1) }.disabled(dimensions.columns >= 6)
                                    Button("Remove column") { resize(selected, rows: dimensions.rows, columns: dimensions.columns - 1) }.disabled(dimensions.columns <= 1)
                                }
                            }
                        }
                    } label: { Image(systemName: "function").frame(width: 44, height: 44) }.accessibilityLabel("Advanced notation")
                }
            }.buttonStyle(.plain).font(.subheadline)
            if let error { Text(error).font(.caption).foregroundStyle(palette.againInk) }
        }.onAppear { selected = document.slots.first?.id; cursor = document.slots.first?.value.count ?? 0 }
        .onChange(of: document) { _, _ in answer = document.complete ? "\\(" + document.latex + "\\)" : "" }
    }
    private func modifierKey(_ title: String, value: Modifier) -> some View {
        Button(title) { modifier = modifier == value ? .base : value }
            .font(.caption.weight(modifier == value ? .bold : .regular))
            .foregroundStyle(modifier == value ? palette.accentInk : palette.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).buttonStyle(.plain)
            .accessibilityAddTraits(modifier == value ? .isSelected : [])
    }
    private func keyButton(_ key: Key) -> some View {
        Button {
            if let template = key.template { insert(template) }
            else if let insertion = key.insertion { write(insertion) }
            else if key.id == "next" { moveSlot(1) }
            else if key.id == "undo" { document.undo(); normalize() }
            else if key.id == "delete", let slot = activeSlot, cursor > 0 {
                let end = slot.value.index(slot.value.startIndex, offsetBy: min(cursor, slot.value.count))
                let start = slot.value.index(before: end)
                _ = document.update(id: slot.id, value: String(slot.value[..<start]) + String(slot.value[end...])); cursor -= 1
            }
            if modifier != .base && !alphabet { modifier = .base }
        } label: {
            Group {
                if key.template == .fraction {
                    VStack(spacing: 2) { Text("□"); Rectangle().frame(width: 16, height: 1); Text("□") }.font(.system(size: 12))
                } else if let symbol = key.symbol { Image(systemName: symbol).font(.body) }
                else { Text(key.title).font(.system(size: textSize.isAccessibilitySize ? 21 : 18)) }
            }.frame(maxWidth: .infinity, minHeight: textSize.isAccessibilitySize ? 52 : 44)
                .contentShape(Rectangle()).foregroundStyle(palette.primaryText)
        }.buttonStyle(.plain).accessibilityLabel(key.template?.title ?? key.title)
            .accessibilityIdentifier("math-key-" + key.id)
    }
    private var activeSlot: MathEntryDocument.Slot? { document.slots.first { $0.id == selected } ?? document.slots.first }
    private func write(_ text: String) {
        guard let slot = activeSlot else { return }
        let position = slot.value.index(slot.value.startIndex, offsetBy: min(cursor, slot.value.count))
        let range = NSRange(position..<position, in: slot.value)
        guard let selection = MathEntryTextSelection(source: slot.value, utf16Range: range) else { return }
        if document.replaceText(text, at: slot.id, selection: selection) == nil { error = "Shorten this expression before adding more." } else { cursor += text.count; error = nil }
    }
    private func insert(_ template: MathEntryTemplate) {
        guard let slot = activeSlot else { return }
        if let next = document.insert(template, at: slot.id, offset: min(cursor, slot.value.count)) { selected = next; cursor = 0; error = nil }
        else { error = "This expression has reached its editing limit." }
    }
    private func moveSlot(_ direction: Int) {
        let slots = document.slots
        guard !slots.isEmpty else { return }
        let index = slots.firstIndex { $0.id == selected } ?? 0
        if direction > 0, index == slots.count - 1, slots[index].label != "Expression", let next = document.appendExpression() {
            selected = next; cursor = 0; return
        }
        selected = slots[max(0, min(slots.count - 1, index + direction))].id
        cursor = activeSlot?.value.count ?? 0
    }
    private func moveCursor(_ direction: Int) {
        guard let slot = activeSlot else { return }
        if cursor + direction < 0 || cursor + direction > slot.value.count { moveSlot(direction) }
        else { cursor += direction }
    }
    private func resize(_ selected: UUID, rows: Int, columns: Int) {
        if document.resize(containing: selected, rows: rows, columns: columns) { error = nil; normalize() }
        else { error = "This would remove entered values. Clear those parts first." }
    }
    private func normalize() { if !document.slots.contains(where: { $0.id == selected }) { selected = document.slots.first?.id }; cursor = activeSlot?.value.count ?? 0 }
    private func display(_ slot: MathEntryDocument.Slot) -> String {
        guard slot.id == (selected ?? document.slots.first?.id) else { return slot.value.isEmpty ? "□" : slot.value }
        let position = slot.value.index(slot.value.startIndex, offsetBy: min(cursor, slot.value.count))
        return String(slot.value[..<position]) + "│" + String(slot.value[position...])
    }
}
