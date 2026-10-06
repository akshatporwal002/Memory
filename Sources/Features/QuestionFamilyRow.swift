import SwiftUI
import LearningCore
import DesignSystem

/// Only saved variants are browsed; gestures never generate content or score a review.
struct QuestionFamilyRow: View {
    @Bindable var model: EngramModel
    let note: Note
    let number: Int
    @State private var position = 0
    @State private var editing: QuestionVariant?
    @Environment(\.engramTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    private var palette: EngramPalette { theme.palette(for: scheme) }
    private var variants: [QuestionVariant] { note.questionFamily?.available(in: model.library, note: note) ?? [] }
    private var selected: QuestionVariant? { position > 0 && position <= variants.count ? variants[position - 1] : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestionReadingView(front: selected?.front ?? note.front, back: selected?.back ?? note.back, number: number, media: model.library.media)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                    move(value.translation.width < 0 ? 1 : -1)
                })
                .accessibilityAction(named: "Next approach") { move(1) }
                .accessibilityAction(named: "Previous approach") { move(-1) }
            if !note.source.isEmpty {
                DisclosureGroup("Source evidence") { Text(note.source).font(.caption).textSelection(.enabled) }
                    .font(.caption).foregroundStyle(palette.secondaryText)
            }
            HStack {
                Button("Edit question") {
                    if let selected { editing = selected }
                    else { model.draft = NoteDraft(note: note); model.editorPresented = true }
                }.font(.caption).frame(minHeight: 44)
                Spacer()
                Menu {
                    if note.kind == .basic {
                        Button(variants.isEmpty ? "Prepare other approaches" : "Replace other approaches") {
                            model.visibleQuestionID = note.id
                            let settings = model.library.liveDecks.first(where: { $0.id == note.deckID })?.understandingSettings ?? model.understanding.defaults
                            let challenge = settings.harderProgression && settings.variantCount > 1 ? " You may include one explicitly harder application with extra reasoning and the same prerequisites; keep the others at the original level." : ""
                            model.questionVariantRequest = "Prepare alternate approaches for question ID \(note.id). Inspect it and retrieve source evidence using its exact front as the query. Keep the same source knowledge, prerequisites, reasoning depth and bounded response length. Prefer explanation and simple application; use comparison/evaluation only when supported. No easier versions, troubleshooting/design jump, or cosmetic paraphrases. Use question_variants to propose up to \(settings.variantCount) variants with their own source-supported answers, objectives and grading rubrics. A separate AI check will validate them. Do not change the original or make new scheduling cards." + challenge
                        }.disabled(model.assistant.busy)
                    }
                    ForEach(model.cards(for: note)) { card in
                        Button(card.suspended ? "Resume card \(card.ordinal + 1)" : "Suspend card \(card.ordinal + 1)") {
                            Task { _ = await model.perform { try await $0.setSuspended(cardID: card.id, suspended: !card.suspended) } }
                        }
                    }
                    Button("Delete question", role: .destructive) { model.deleteNote = note }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Question \(number) actions")
            }.foregroundStyle(palette.secondaryText).disabled(model.busy)
            if !variants.isEmpty {
                HStack(spacing: 7) {
                    ForEach(0...variants.count, id: \.self) { index in
                        Button { select(index) } label: {
                            Circle().fill(index == position ? palette.accentInk : palette.secondaryText.opacity(0.3)).frame(width: 6, height: 6)
                                .frame(width: 24, height: 28)
                        }.buttonStyle(.plain)
                            .accessibilityLabel(index == 0 ? "Original question" : "\(variants[index - 1].approach.rawValue) approach")
                            .accessibilityValue(index == position ? "Selected" : "")
                    }
                }.frame(maxWidth: .infinity)
                    .accessibilityIdentifier("question-approach-dots-\(note.id)")
            }
            Divider()
        }
        .onChange(of: variants) { _, _ in position = 0 }
        .sheet(item: $editing) { variant in QuestionVariantEditor(model: model, note: note, variant: variant) }
    }
    private func move(_ delta: Int) { select(position + delta) }
    private func select(_ index: Int) {
        guard (0...variants.count).contains(index), index != position else { return }
        position = index
        if let selected {
            Task { _ = await model.perform { try await $0.recordQuestionVariantExposure(noteID: note.id, variantID: selected.id) } }
        }
    }
}

private struct QuestionVariantEditor: View {
    @Bindable var model: EngramModel
    let note: Note
    @State var variant: QuestionVariant
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Question") { TextEditor(text: $variant.front).frame(minHeight: 100) }
                Section("Answer") { TextEditor(text: $variant.back).frame(minHeight: 100) }
                Section("Learning objective") { TextEditor(text: $variant.objective) }
                Section("Grading rubric") { TextEditor(text: $variant.rubric) }
                Section("Review source support and comparable reasoning depth") {
                    ForEach(variant.evidence) { Text($0.text).font(.caption) }
                }
            }.navigationTitle("Edit question")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save reviewed version") {
                            Task {
                                let success = await model.perform { service in
                                    guard let current = model.library.liveNotes.first(where: { $0.id == note.id }),
                                          current.questionFamily == note.questionFamily else { throw EngramError.conflict }
                                    var variants = current.questionFamily?.variants ?? []
                                    guard let index = variants.firstIndex(where: { $0.id == variant.id }) else { throw EngramError.missing("variant") }
                                    var edited = variant
                                    if edited.front != variants[index].front || edited.back != variants[index].back || edited.rubric != variants[index].rubric || edited.objective != variants[index].objective || edited.approach != variants[index].approach || edited.evidence != variants[index].evidence { edited.revision = (variants[index].revision ?? 1) + 1 }
                                    let checked = try await model.understanding.validateVariants([edited], note: current, model: model, editingExisting: true)
                                    variants[index] = checked[0]
                                    try await service.saveQuestionVariants(noteID: note.id, originalFront: note.front, originalBack: note.back, variants: variants, expectedRevision: model.library.revision)
                                }
                                if success { dismiss() }
                            }
                        }.disabled(model.busy)
                    }
                }
        }
    }
}

struct QuestionVariantReview: View {
    @Bindable var model: EngramModel
    private var variants: [QuestionVariant] {
        guard let call = model.assistant.pendingConfirmation,
              let args = try? JSONSerialization.jsonObject(with: Data(call.arguments.utf8)) as? [String: String],
              let json = args["variants"] else { return [] }
        return (try? JSONDecoder().decode([QuestionVariant].self, from: Data(json.utf8))) ?? []
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Check that each approach uses the same material and similar reasoning depth. Difficulty has not been calibrated.").font(.subheadline)
                    ForEach(variants) { variant in
                        Text(variant.approach.rawValue.capitalized).font(.headline)
                        QuestionReadingView(front: variant.front, back: variant.back, media: model.library.media)
                        Text("Objective: " + variant.objective).font(.subheadline)
                        Text("Grading rubric: " + variant.rubric).font(.subheadline)
                        DisclosureGroup("Source evidence") { ForEach(variant.evidence) { Text($0.text).font(.caption) } }
                        Divider()
                    }
                }.padding()
            }.navigationTitle("Review approaches")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Task { await model.assistant.reject(model: model) } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save reviewed approaches") { Task { await model.assistant.confirm(model: model) } }.disabled(variants.isEmpty)
                    }
                }
        }
    }
}
