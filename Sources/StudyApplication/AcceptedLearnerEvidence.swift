import Foundation
import LearningCore

/// Read-only bridge from the existing assessment acceptance boundary. No FSRS mutation.
/// Assistance/mapping/timing are supplied only when explicitly recorded; no legacy inference.
public enum AcceptedLearnerEvidence {
    public static func recall(attemptID: String, revision: Int, in library: LibrarySnapshot,
                              mapping: ReviewedSkillMapping? = nil, recordedAssistance: Bool? = nil,
                              delaySeconds: Double? = nil, studySeconds: Double? = nil) throws -> LearnerEvidence {
        guard let attempt = library.answerAttempts?.first(where: { $0.id == attemptID }), attempt.committedAt != nil,
              let review = library.activeReviews.first(where: { $0.id == "answer-" + attempt.presentationID && $0.cardID == attempt.cardID }),
              let assessment = review.assessment, assessment == attempt.assessment,
              review.gradingMethod != "manual",
              assessment.rating == review.rating,
              ["ai", "local-exact", "mcq-local"].contains(assessment.method),
              recordedAssistance != false || !attempt.assisted else { throw LearnerError.invalidEvidence }
        // Partial and unclear outcomes cannot be turned into binary failures or successes.
        let correct: Bool? = review.gradingMethod != assessment.method ? nil : assessment.outcome == .correct ? true : assessment.outcome == .incorrect ? false : nil
        let row = LearnerEvidence(attemptID: attempt.id, revision: revision, questionID: attempt.cardID,
            questionVersion: attempt.cardVersion, occurredAt: attempt.createdAt, kind: .recall,
            mapping: mapping, assisted: recordedAssistance, acceptance: .accepted, correct: correct,
            gradingMethod: assessment.method, delaySeconds: delaySeconds, studySeconds: studySeconds)
        try row.validate(); return row
    }
}
