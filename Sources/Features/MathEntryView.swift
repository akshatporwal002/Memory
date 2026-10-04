import SwiftUI
import LearningCore
import DesignSystem

/// Notation entry only. Accepting inserts portable LaTeX into the existing answer;
/// it neither evaluates expressions nor changes the question's grading rules.
struct MathEntryView: View {
    private enum Shape: String, Identifiable { case matrix, piecewise; var id: String { rawValue } }
    var insert: (String) -> Void
    @State private var document = MathEntryDocument()
    @State private var category = MathEntryCategory.arithmetic
    @State private var selected: UUID?
    @State private var carets: [UUID: MathEntryTextSelection] = [:]
    @State private var error: String?
    @State private var shape: Shape?
    @State private var rows = 2
    @State private var columns = 2
    @State private var resizingSlot: UUID?
    @State private var confirmShrink = false
    @FocusState private var focused: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var symbols: [String] {
        category == .greek ? ["α", "β", "γ", "δ", "ε", "ζ", "η", "θ", "ι", "κ", "λ", "μ", "ν", "ξ", "ο", "π", "ρ", "σ", "τ", "υ", "φ", "χ", "ψ", "ω", "Γ", "Δ", "Θ", "Λ", "Ξ", "Π", "Σ", "Φ", "Ψ", "Ω"] : ["+", "−", "×", "÷", "=", "<", ">", "π", "θ", "∞"]
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RichContentView(source: "$$\n" + document.latex + "\n$$")
                            .frame(maxWidth: .infinity, minHeight: 84).accessibilityLabel("Equation preview")
                        Divider()
                        HStack(spacing: 20) {
                            Button("Undo", systemImage: "arrow.uturn.backward") { document.undo(); normalizeSelection() }.disabled(!document.canUndo)
                            Button("Redo", systemImage: "arrow.uturn.forward") { document.redo(); normalizeSelection() }.disabled(!document.canRedo)
                            Spacer()
                            if let selected, document.canRemoveTemplate(containing: selected) {
                                Menu("Structure") {
                                    if let dimensions = document.dimensions(containing: selected) {
                                        Button("Resize " + (dimensions.kind == .matrix ? "matrix" : "cases")) {
                                            resizingSlot = selected; rows = dimensions.rows; columns = dimensions.columns
                                            focused = nil; error = nil
                                            shape = dimensions.kind == .matrix ? .matrix : .piecewise
                                        }.accessibilityIdentifier("math-resize")
                                    }
                                    Button("Remove template") {
                                        if document.removeTemplate(containing: selected) { normalizeSelection() }
                                        else { error = "Shorten this expression before removing the template." }
                                    }
                                }
                            }
                        }.buttonStyle(.plain).font(.subheadline).frame(minHeight: 44)
                        if geometry.size.width >= 700 && !typeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 28) { fields.frame(maxWidth: .infinity); paletteView.frame(width: 320) }
                        } else { fields; paletteView }
                        if let error { Text(error).engramErrorText().font(.caption) }
                        Text("Notation only · no calculation or solving").font(.caption).foregroundStyle(palette.secondaryText)
                    }.padding(20).frame(maxWidth: 960).frame(maxWidth: .infinity)
                }
            }.engramCanvas().navigationTitle("Equation").engramInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") { insert("\\(" + document.latex + "\\)"); dismiss() }
                        .disabled(!document.complete).accessibilityIdentifier("math-entry-insert")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Previous", systemImage: "chevron.left") { move(-1) }
                    Button("Next", systemImage: "chevron.right") { move(1) }
                    Spacer(); Button("Done") { focused = nil }
                }
            }
            .onAppear { selected = document.slots.first?.id }
            .onChange(of: focused) { _, value in if let value { selected = value } }
            .sheet(item: $shape) { kind in
                NavigationStack {
                    Form {
                        Stepper(kind == .matrix ? "Rows: \(rows)" : "Cases: \(rows)", value: $rows, in: 1...6).accessibilityIdentifier("math-dimension-rows")
                        if kind == .matrix { Stepper("Columns: \(columns)", value: $columns, in: 1...6).accessibilityIdentifier("math-dimension-columns") }
                        if let resizingSlot, document.resizeWouldDiscardContent(containing: resizingSlot, rows: rows, columns: columns) {
                            Text("This removes values outside the new dimensions. Undo can restore them.").font(.footnote).foregroundStyle(palette.secondaryText)
                        }
                        Button((resizingSlot == nil ? "Insert " : "Resize ") + (kind == .matrix ? "matrix" : "piecewise expression")) {
                            if let resizingSlot, document.resizeWouldDiscardContent(containing: resizingSlot, rows: rows, columns: columns) { confirmShrink = true }
                            else { applyDimensions(kind) }
                        }.accessibilityIdentifier("math-dimensions-apply")
                        if let error { Text(error).engramErrorText().font(.footnote) }
                    }.modifier(UtilityListStyle()).navigationTitle(kind == .matrix ? "Matrix size" : "Piecewise cases")
                        .engramInlineTitle().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { shape = nil } } }
                }.presentationDetents([.medium])
                    .confirmationDialog("Remove values outside the new dimensions?", isPresented: $confirmShrink, titleVisibility: .visible) {
                        Button("Resize and remove values", role: .destructive) { applyDimensions(kind, allowDiscardingContent: true) }
                        Button("Keep current dimensions", role: .cancel) { }
                    }
            }
        }
    }
    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.slots) { slot in
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.label).font(.caption).foregroundStyle(palette.secondaryText)
                    slotInput(slot)
                        .textFieldStyle(.plain).font(.body).focused($focused, equals: slot.id)
                        .autocorrectionDisabled().frame(minHeight: 44)
                        .accessibilityIdentifier("math-slot-" + String(document.slots.firstIndex { $0.id == slot.id } ?? 0))
                    Divider().overlay(selected == slot.id ? palette.accent : .clear)
                }
            }
        }
    }
    private var paletteView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Notation category", selection: $category) {
                ForEach(MathEntryCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("math-category")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86))], spacing: 8) {
                ForEach(MathEntryTemplate.allCases.filter { $0.category == category }, id: \.self) { template in
                    Button(template.title) {
                        if template == .matrix || template == .piecewise {
                            rows = 2; columns = 2; focused = nil; resizingSlot = nil; error = nil
                            shape = template == .matrix ? .matrix : .piecewise; return
                        }
                        guard let id = selected ?? document.slots.first?.id else { return }
                        let next: UUID?
                        if let caret = carets[id] { next = document.insert(template, at: id, selection: caret) }
                        else { next = document.insert(template, at: id) }
                        if let next { carets.removeValue(forKey: id); selected = next; focused = nil; error = nil }
                        else { error = "This expression has reached its editing limit." }
                    }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("math-template-" + template.rawValue)
                }
            }.buttonStyle(.plain).foregroundStyle(palette.accentInk)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button(symbol) {
                            guard let slot = document.slots.first(where: { $0.id == selected }) ?? document.slots.first else { return }
                            if let caret = document.replaceText(symbol, at: slot.id, selection: carets[slot.id]) { carets[slot.id] = caret; error = nil }
                            else { error = "Select the insertion point again, or shorten this expression." }
                        }.font(.title3).frame(minWidth: 44, minHeight: 44)
                    }
                }
            }.buttonStyle(.plain)
        }
    }
    private func move(_ direction: Int) {
        let slots = document.slots
        guard !slots.isEmpty else { return }
        let current = slots.firstIndex { $0.id == (focused ?? selected) } ?? 0
        let next = max(0, min(slots.count - 1, current + direction))
        selected = slots[next].id; focused = slots[next].id
    }
    @ViewBuilder private func slotInput(_ slot: MathEntryDocument.Slot) -> some View {
        let value = Binding<String>(get: { document.slots.first { $0.id == slot.id }?.value ?? "" },
            set: { if !document.update(id: slot.id, value: $0) { error = "This expression is too long. Shorten it before adding more." } else { error = nil } })
        if #available(iOS 18.0, macOS 15.0, *) {
            MathCaretTextField(prompt: "Enter " + slot.label.lowercased(), text: value,
                caret: Binding(get: { carets[slot.id] }, set: { carets[slot.id] = $0 }))
        } else {
            TextField("Enter " + slot.label.lowercased(), text: value)
        }
    }
    private func applyDimensions(_ kind: Shape, allowDiscardingContent: Bool = false) {
        if let resizingSlot {
            guard document.resize(containing: resizingSlot, rows: rows, columns: columns, allowDiscardingContent: allowDiscardingContent) else {
                error = "These dimensions exceed the expression limits. Your values were kept."; return
            }
            normalizeSelection()
        } else if let id = selected ?? document.slots.first?.id {
            let next: UUID?
            if let caret = carets[id] {
                next = kind == .matrix ? document.insertMatrix(rows: rows, columns: columns, at: id, selection: caret) : document.insertPiecewise(cases: rows, at: id, selection: caret)
            } else {
                next = kind == .matrix ? document.insertMatrix(rows: rows, columns: columns, at: id) : document.insertPiecewise(cases: rows, at: id)
            }
            guard let next else { error = "This expression has reached its editing limit."; return }
            carets.removeValue(forKey: id); selected = next; focused = nil; error = nil
        }
        shape = nil
    }
    private func normalizeSelection() {
        carets.removeAll()
        focused = nil
        if !document.slots.contains(where: { $0.id == selected }) { selected = document.slots.first?.id }
        error = nil
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct MathCaretTextField: View {
    var prompt: String
    @Binding var text: String
    @Binding var caret: MathEntryTextSelection?
    @State private var nativeSelection: TextSelection?
    var body: some View {
        TextField(prompt, text: $text, selection: $nativeSelection)
            .onChange(of: nativeSelection) { _, value in
                guard let value, case .selection(let range) = value.indices,
                      range.lowerBound >= text.startIndex, range.upperBound <= text.endIndex else { return }
                caret = MathEntryTextSelection(source: text, utf16Range: NSRange(range, in: text))
            }
            .onChange(of: caret) { _, value in
                guard let value, value.source == text, let range = Range(value.utf16Range, in: text) else { return }
                nativeSelection = TextSelection(range: range)
            }
    }
}
