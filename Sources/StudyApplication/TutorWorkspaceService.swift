import Foundation
import LearningCore

/// Local contract for the future authenticated server operations. This grants no hosted access.
public enum TutorWorkspaceService {
    public static let activeStudentLimit = 5

    public static func accept(_ membership: TutorStudentMembership, actorID: UUID,
                              expectedVersion: Int, workspace: inout TutorWorkspace) throws {
        guard actorID == membership.studentID, membership.consent == .granted else {
            throw EngramError.invalid("Student consent is required before sharing.")
        }
        try version(expectedVersion, workspace)
        if workspace.memberships.contains(where: { $0.studentID == actorID && $0.consent == .granted }) { return }
        guard workspace.memberships.filter({ $0.consent == .granted }).count < activeStudentLimit else {
            throw EngramError.invalid("This workspace already has five active students.")
        }
        workspace.memberships.removeAll { $0.studentID == actorID }
        workspace.memberships.append(membership); workspace.version += 1
    }

    public static func publish(_ assignment: TutorAssignment, actorID: UUID,
                               expectedVersion: Int, workspace: inout TutorWorkspace) throws {
        try owner(actorID, workspace); try version(expectedVersion, workspace)
        guard authorizedStudent(assignment.studentID, workspace), !assignment.questionIDs.isEmpty,
              assignment.revision > 0, !assignment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EngramError.invalid("Assignments require an accepted student and content snapshot.")
        }
        if let previous = workspace.assignments.last(where: { $0.id == assignment.id }) {
            guard previous.studentID == assignment.studentID, assignment.revision == previous.revision + 1 else {
                throw EngramError.conflict
            }
            // Preserve prior revisions and their learner progress; never reset on publication.
        } else if assignment.revision != 1 { throw EngramError.conflict }
        guard !workspace.assignments.contains(where: { $0.id == assignment.id && $0.revision == assignment.revision }) else {
            throw EngramError.conflict
        }
        workspace.assignments.append(assignment); workspace.version += 1
    }

    public static func share(_ summary: TutorProgressSummary, assignmentID: UUID, actorID: UUID,
                             expectedVersion: Int, workspace: inout TutorWorkspace) throws {
        try version(expectedVersion, workspace)
        guard let assignment = workspace.assignments.last(where: { $0.id == assignmentID }),
              assignment.studentID == actorID, !assignment.withdrawn,
              authorizedStudent(actorID, workspace),
              summary.reviewedQuestionIDs.isSubset(of: assignment.questionIDs),
              summary.correctCount >= 0, summary.correctCount <= summary.reviewedQuestionIDs.count,
              summary.sharedMisconceptions.count <= 50,
              summary.sharedMisconceptions.allSatisfy({ $0.count <= 2_000 }) else {
            throw EngramError.invalid("Progress must belong to this student's active assignment.")
        }
        workspace.progress[assignmentID] = summary; workspace.version += 1
    }

    public static func progress(assignmentID: UUID, actorID: UUID,
                                workspace: TutorWorkspace) throws -> TutorProgressSummary? {
        guard let assignment = workspace.assignments.last(where: { $0.id == assignmentID }),
              !assignment.withdrawn, authorizedStudent(assignment.studentID, workspace),
              actorID == workspace.ownerID || actorID == assignment.studentID else {
            throw EngramError.invalid("This assignment is not available to this account.")
        }
        return workspace.progress[assignmentID]
    }

    public static func revoke(studentID: UUID, actorID: UUID,
                              expectedVersion: Int, workspace: inout TutorWorkspace) throws {
        try version(expectedVersion, workspace)
        guard actorID == workspace.ownerID || actorID == studentID,
              let index = workspace.memberships.firstIndex(where: { $0.studentID == studentID }) else {
            throw EngramError.invalid("This membership cannot be changed by this account.")
        }
        workspace.memberships[index].consent = .revoked
        for index in workspace.assignments.indices where workspace.assignments[index].studentID == studentID {
            workspace.assignments[index].withdrawn = true
            workspace.progress.removeValue(forKey: workspace.assignments[index].id)
        }
        workspace.version += 1
    }

    private static func authorizedStudent(_ id: UUID, _ workspace: TutorWorkspace) -> Bool {
        workspace.memberships.contains { $0.studentID == id && $0.consent == .granted }
    }
    private static func owner(_ id: UUID, _ workspace: TutorWorkspace) throws {
        guard id == workspace.ownerID else { throw EngramError.invalid("Only this workspace's tutor can publish assignments.") }
    }
    private static func version(_ expected: Int, _ workspace: TutorWorkspace) throws {
        guard expected == workspace.version else { throw EngramError.conflict }
    }
}
