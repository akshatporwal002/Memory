import SwiftUI
import LearningCore
import DesignSystem

struct TutorWorkspaceView: View {
    @Bindable var model: EngramModel
    @State private var query = ""
    @State private var adding = false
    @State private var subject = ""
    @State private var deckID = ""
    @State private var inviting = false
    private var workspace: TutorWorkspace? { model.tutor.workspace }
    private var subjects: [String] { Array(Set((workspace?.drafts ?? []).map(\.subject))).sorted() }
    var body: some View {
        List {
            if !model.tutor.activated {
                EngramListSection {
                    Text("A workspace for your teaching.").font(.title2)
                    Text("Organize subjects and assignments, then follow shared student progress.").engramSecondaryText()
                    Button("Activate tutor workspace") { Task { await model.tutor.activate(model) } }.frame(minHeight: 44)
                } footer: { Text("Creating and exploring your workspace is free. Payment is required only when inviting students.") }
            } else if let workspace {
                EngramListSection {
                    NavigationLink { TutorStudentsView(workspace: workspace, title: "All students") } label: { Text("All students") }
                    Button("Invite student", systemImage: "person.badge.plus") { inviting = true }
                }
                EngramListSection("Subjects") {
                    ForEach(subjects.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { name in
                        NavigationLink {
                            List {
                                EngramListSection("Notebooks") {
                                    ForEach((workspace.drafts ?? []).filter { $0.subject == name }) { draft in
                                        NavigationLink { TutorStudentsView(workspace: workspace, title: draft.title, deckID: draft.sourceDeckID) } label: { Label(draft.title, systemImage: "book.closed") }
                                    }
                                }
                            }.modifier(UtilityListStyle()).navigationTitle(name)
                        } label: { Label(name, systemImage: "folder") }
                    }
                    if subjects.isEmpty { Text("Add your first teaching notebook.").engramSecondaryText() }
                    Button("Add notebook", systemImage: "plus") { adding = true }
                }
            }
            EngramListSection("Sharing") {
                Text("Students choose whether to share assigned progress and misconception summaries. Their answers, recordings and chats stay private.").engramSecondaryText()
            }
            if let error = model.tutor.error { EngramListSection { Text(error).engramErrorText() } }
        }.modifier(UtilityListStyle()).navigationTitle("Tutor").searchable(text: $query, prompt: "Find a subject")
        .task(id: model.cloud.userID?.uuidString ?? model.cloud.localProfileID ?? "local") { await model.tutor.configure(model) }
        .sheet(isPresented: $adding) { teachingNotebookForm }
        .sheet(isPresented: $inviting) {
            NavigationStack {
                List {
                    EngramListSection {
                        Text("Invite students when your tutor plan is ready.")
                        Text("Invitations require a server-verified purchase and accepted sharing consent. Your draft workspace remains free.").engramSecondaryText()
                        Text("Purchase verification and hosted invitations are awaiting configuration. No payment has been taken.").font(.caption).engramSecondaryText()
                    }
                }.modifier(UtilityListStyle()).navigationTitle("Invite student")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { inviting = false } } }
            }.presentationDetents([.medium])
        }
    }
    private var teachingNotebookForm: some View {
        NavigationStack {
            List {
                EngramListSection {
                    TextField("Subject", text: $subject).textFieldStyle(.plain)
                    Picker("Notebook", selection: $deckID) {
                        Text("Choose notebook").tag("")
                        ForEach(model.library.liveDecks) { Text($0.name).tag($0.id) }
                    }
                } footer: { Text("A teaching draft does not add student assignments to your personal review queue.") }
            }.modifier(UtilityListStyle()).navigationTitle("Teaching notebook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard var next = workspace, let deck = model.library.liveDecks.first(where: { $0.id == deckID }) else { return }
                        next.drafts = (next.drafts ?? []).filter { $0.sourceDeckID != deckID } + [TutorDeckDraft(sourceDeckID: deckID, title: deck.name, subject: subject.trimmingCharacters(in: .whitespacesAndNewlines))]
                        Task { await model.tutor.save(next); if model.tutor.error == nil { adding = false } }
                    }.disabled(deckID.isEmpty || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subject.count > 120)
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

private struct TutorStudentsView: View {
    let workspace: TutorWorkspace
    let title: String
    var deckID: String? = nil
    @State private var query = ""
    private var students: [TutorStudentMembership] {
        workspace.memberships.filter { member in
            member.consent == .granted && (query.isEmpty || (member.displayName ?? "Student").localizedCaseInsensitiveContains(query)) &&
            (deckID == nil || workspace.assignments.contains { $0.studentID == member.studentID && $0.sourceDeckID == deckID && !$0.withdrawn })
        }.sorted { ($0.displayName ?? "").localizedStandardCompare($1.displayName ?? "") == .orderedAscending }
    }
    var body: some View {
        List {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a student", text: $query).textFieldStyle(.plain).accessibilityIdentifier("tutor-student-search")
            }.frame(minHeight: 44)
            EngramListSection("Students") {
                ForEach(students) { student in
                    NavigationLink { studentDetail(student) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(student.displayName ?? "Student")
                            if let progress = progress(student.studentID) {
                                ProgressView(value: Double(progress.reviewed), total: Double(max(1, assignments(student.studentID).reduce(0) { $0 + $1.questionIDs.count })))
                                    .tint(.primary).accessibilityLabel("Assigned questions reviewed")
                            } else { Text("No shared activity yet").font(.caption).engramSecondaryText() }
                        }.padding(.vertical, 6)
                    }
                }
                if students.isEmpty { Text(query.isEmpty ? "Students appear here after accepting an invitation and progress sharing." : "No matching students").engramSecondaryText() }
            }
        }.modifier(UtilityListStyle()).navigationTitle(title)
    }
    private func assignments(_ student: UUID) -> [TutorAssignment] {
        Dictionary(grouping: workspace.assignments, by: \.id).values.compactMap { $0.max { $0.revision < $1.revision } }
            .filter { $0.studentID == student && !$0.withdrawn && (deckID == nil || $0.sourceDeckID == deckID) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private struct StudentProgress { let reviewed: Int; let correct: Int; let lastActivity: Date?; let misconceptions: [String] }
    private func progress(_ student: UUID) -> StudentProgress? {
        let scoped = assignments(student).compactMap { assignment -> (TutorAssignment, TutorProgressSummary)? in
            workspace.progress[assignment.id].map { (assignment, $0) }
        }
        guard !scoped.isEmpty else { return nil }
        return StudentProgress(reviewed: scoped.reduce(0) { $0 + $1.1.reviewedQuestionIDs.intersection($1.0.questionIDs).count },
            correct: scoped.reduce(0) { $0 + $1.1.correctCount }, lastActivity: scoped.compactMap { $0.1.lastActivity }.max(),
            misconceptions: Array(Set(scoped.flatMap { $0.1.sharedMisconceptions })).sorted())
    }
    private func assigned(_ student: UUID) -> Set<UUID> { Set(assignments(student).flatMap(\.questionIDs)) }
    private func studentDetail(_ student: TutorStudentMembership) -> some View {
        List {
            if let progress = progress(student.studentID) {
                EngramListSection("Learning progress") {
                    LabeledContent("Assignment questions reviewed", value: String(progress.reviewed))
                    LabeledContent("Correct answers", value: String(progress.correct))
                    if let last = progress.lastActivity { LabeledContent("Last activity", value: last.formatted(date: .abbreviated, time: .shortened)) }
                }
                EngramListSection("Shared misconceptions") {
                    ForEach(progress.misconceptions, id: \.self) { Text($0) }
                    if progress.misconceptions.isEmpty { Text("No shared concerns").engramSecondaryText() }
                }
            }
            EngramListSection("Assignments") {
                ForEach(assignments(student.studentID)) { assignment in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(assignment.title)
                        if let due = assignment.dueAt { Text("Due " + due.formatted(date: .abbreviated, time: .omitted)).font(.caption).engramSecondaryText() }
                    }
                }
            }
        }.modifier(UtilityListStyle()).navigationTitle(student.displayName ?? "Student")
    }
}
