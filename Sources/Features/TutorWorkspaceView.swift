import SwiftUI
import LearningCore
import PersistenceAdapters
import DesignSystem

/// Local authoring shell; invitations and shared student data remain unavailable until backend activation.
struct TutorWorkspaceView: View {
    @Bindable var model: EngramModel
    @State private var workspaces: [TutorWorkspace] = []
    @State private var title = ""
    @State private var error: String?
    @State private var saving = false
    @State private var ownerID: UUID?
    @FocusState private var editingName: Bool
    private var accountKey: String { model.cloud.userID?.uuidString ?? model.cloud.localProfileID ?? "local" }
    private static let repository: TutorWorkspaceRepository = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return TutorWorkspaceRepository(directory: root.appendingPathComponent("Engram/TutorDrafts", isDirectory: true))
    }()

    var body: some View {
        List {
            EngramListSection {
                Text("A workspace for your students.").engramSecondaryText()
            } footer: { Text("Student invitations and progress sharing are not enabled yet.") }
            EngramListSection("Workspaces") {
                ForEach(workspaces) { workspace in
                    NavigationLink {
                        TutorWorkspaceDetail(workspace: workspace)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(workspace.title)
                            Text("Local draft · \(workspace.assignments.count) assignments")
                                .font(model.theme.font(.metadata)).engramSecondaryText()
                        }.padding(.vertical, 4)
                    }
                }
                if workspaces.isEmpty { Text("Your tutor workspaces will appear here.").engramSecondaryText() }
            }
            EngramListSection("New workspace") {
                TextField("Workspace name", text: $title)
                    .focused($editingName).onSubmit { Task { await create() } }
                    .accessibilityIdentifier("tutor-workspace-name")
                Button { Task { await create() } } label: {
                    Label("Create workspace", systemImage: "plus").frame(minHeight: 44)
                }
                .disabled(saving || ownerID == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("tutor-create-workspace")
            }
            EngramListSection("Sharing") {
                Text("Tutors see assigned progress and accepted misconception summaries.")
                    .engramSecondaryText().fixedSize(horizontal: false, vertical: true)
                Text("Answers, recordings and chats stay private.")
                    .engramSecondaryText().fixedSize(horizontal: false, vertical: true)
                Text("Guardian consent is required before a minor’s progress is shared.")
                    .engramSecondaryText().fixedSize(horizontal: false, vertical: true)
            }
            if let error { EngramListSection { Text(error).accessibilityLabel("Tutor workspace error: \(error)") } }
        }
        .modifier(UtilityListStyle()).navigationTitle("Tutor")
        .task(id: accountKey) { await load() }
    }

    @MainActor private func load() async {
        let account = accountKey
        workspaces = []; ownerID = nil; error = nil
        let key = "engram.tutor.draftOwner." + account
        let id = model.cloud.userID ?? UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        do {
            let values = try await Self.repository.load(ownerID: id)
            guard account == accountKey else { return }
            ownerID = id; workspaces = values
        } catch { if account == accountKey { self.error = error.localizedDescription } }
    }

    @MainActor private func create() async {
        let account = accountKey
        guard !saving, let ownerID else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else { error = "Use a name with 1–120 characters."; return }
        saving = true; error = nil; defer { saving = false }
        do {
            let workspace = TutorWorkspace(ownerID: ownerID, title: name)
            try await Self.repository.save(workspace, expectedVersion: nil)
            guard account == accountKey else { return }
            workspaces.append(workspace); title = ""; editingName = false
        } catch { if account == accountKey { self.error = error.localizedDescription } }
    }
}

private struct TutorWorkspaceDetail: View {
    let workspace: TutorWorkspace
    var body: some View {
        List {
            EngramListSection("Students") {
                Text("No students connected yet.")
                Text("Invitation links will appear here once authenticated sharing and consent are ready.").engramSecondaryText()
            }
            EngramListSection("Assignments") {
                Text("No assignments published yet.").engramSecondaryText()
            }
            EngramListSection("Progress & misconceptions") {
                Text("Assigned-work summaries will appear here after a student accepts sharing. This workspace does not have access to anyone's private learning data.")
                    .engramSecondaryText()
            }
        }.modifier(UtilityListStyle()).navigationTitle(workspace.title)
    }
}
