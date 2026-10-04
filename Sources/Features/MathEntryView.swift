import SwiftUI
import LearningCore
import DesignSystem

/// Notation entry only. Accepting inserts portable LaTeX into the existing answer;
/// it neither evaluates expressions nor changes the question's grading rules.
struct MathEntryView: View {
    var insert: (String) -> Void
    @State private var document = MathEntryDocument()
    @State private var category = MathEntryCategory.arithmetic
    @State private var selected: UUID?
    @State private var error: String?
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
        }
    }
    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(document.slots) { slot in
                VStack(alignment: .leading, spacing: 4) {
                    Text(slot.label).font(.caption).foregroundStyle(palette.secondaryText)
                    TextField("Enter " + slot.label.lowercased(), text: Binding(
                        get: { document.slots.first { $0.id == slot.id }?.value ?? "" },
                        set: { if !document.update(id: slot.id, value: $0) { error = "This expression is too long. Shorten it before adding more." } else { error = nil } }))
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
                        guard let id = selected ?? document.slots.first?.id else { return }
                        if let next = document.insert(template, at: id) { selected = next; focused = nil; error = nil }
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
                            if !document.update(id: slot.id, value: slot.value + symbol) { error = "This expression is too long." }
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
}
