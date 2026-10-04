import XCTest
import LearningCore
import StudyApplication

final class TutorWorkspaceTests: XCTestCase {
    func testAssignmentRevisionsRemainSequentialAndTutorScoped() throws {
        let owner = UUID(), student = UUID(), question = UUID(), assignmentID = UUID()
        var workspace = TutorWorkspace(ownerID: owner, title: "AWS")
        try TutorWorkspaceService.accept(.init(studentID: student, consent: .granted), actorID: student,
            expectedVersion: 1, workspace: &workspace)
        for revision in 1...3 {
            let assignment = TutorAssignment(id: assignmentID, studentID: student, revision: revision,
                title: "Revision \(revision)", questionIDs: [question])
            XCTAssertThrowsError(try TutorWorkspaceService.publish(assignment, actorID: student,
                expectedVersion: workspace.version, workspace: &workspace))
            try TutorWorkspaceService.publish(assignment, actorID: owner,
                expectedVersion: workspace.version, workspace: &workspace)
        }
        XCTAssertEqual(workspace.assignments.map(\.revision), [1, 2, 3])
        XCTAssertThrowsError(try TutorWorkspaceService.publish(.init(id: assignmentID, studentID: UUID(),
            revision: 4, title: "Wrong learner", questionIDs: [question]), actorID: owner,
            expectedVersion: workspace.version, workspace: &workspace))
    }
    func testGuardianAndPendingConsentCannotShareOrConsumeCapacity() throws {
        let owner = UUID(), student = UUID()
        var workspace = TutorWorkspace(ownerID: owner, title: "AWS")
        for consent in [TutorSharingConsent.pending, .guardianRequired, .revoked] {
            XCTAssertThrowsError(try TutorWorkspaceService.accept(.init(studentID: student, consent: consent),
                actorID: student, expectedVersion: 1, workspace: &workspace))
        }
        XCTAssertEqual(workspace.version, 1)
        XCTAssertTrue(workspace.memberships.isEmpty)
    }
    func testCapacityAndConcurrentVersionChecks() throws {
        var workspace = TutorWorkspace(ownerID: UUID(), title: "AWS")
        for _ in 0..<5 {
            let student = UUID()
            try TutorWorkspaceService.accept(.init(studentID: student, consent: .granted), actorID: student,
                expectedVersion: workspace.version, workspace: &workspace)
        }
        let extra = UUID()
        XCTAssertThrowsError(try TutorWorkspaceService.accept(.init(studentID: extra, consent: .granted),
            actorID: extra, expectedVersion: workspace.version, workspace: &workspace))
        XCTAssertThrowsError(try TutorWorkspaceService.revoke(studentID: workspace.memberships[0].studentID,
            actorID: workspace.ownerID, expectedVersion: 1, workspace: &workspace))
    }
    func testAssignedProjectionOnlyAndRevocationRemovesAccess() throws {
        let owner = UUID(), student = UUID(), question = UUID()
        var workspace = TutorWorkspace(ownerID: owner, title: "AWS")
        try TutorWorkspaceService.accept(.init(studentID: student, consent: .granted), actorID: student,
            expectedVersion: 1, workspace: &workspace)
        let assignment = TutorAssignment(studentID: student, title: "Cloud basics", questionIDs: [question])
        try TutorWorkspaceService.publish(assignment, actorID: owner, expectedVersion: 2, workspace: &workspace)
        XCTAssertThrowsError(try TutorWorkspaceService.share(.init(reviewedQuestionIDs: [UUID()]),
            assignmentID: assignment.id, actorID: student, expectedVersion: 3, workspace: &workspace))
        try TutorWorkspaceService.share(.init(reviewedQuestionIDs: [question], correctCount: 1,
            sharedMisconceptions: ["CloudFront is a CDN"]), assignmentID: assignment.id, actorID: student,
            expectedVersion: 3, workspace: &workspace)
        XCTAssertNotNil(try TutorWorkspaceService.progress(assignmentID: assignment.id, actorID: owner, workspace: workspace))
        XCTAssertThrowsError(try TutorWorkspaceService.progress(assignmentID: assignment.id, actorID: UUID(), workspace: workspace))
        try TutorWorkspaceService.revoke(studentID: student, actorID: student, expectedVersion: 4, workspace: &workspace)
        XCTAssertThrowsError(try TutorWorkspaceService.progress(assignmentID: assignment.id, actorID: owner, workspace: workspace))
        XCTAssertTrue(workspace.progress.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(TutorWorkspace.self, from: JSONEncoder().encode(workspace)), workspace)
    }
}
