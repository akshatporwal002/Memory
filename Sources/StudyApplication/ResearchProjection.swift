import Foundation
import LearningCore

extension StudyService {
    public func estimatedRecallBefore(_ review: ReviewEvent, settings: StudySettings) -> Double? {
        (scheduler as? any MemoryEstimating)?.recallProbability(state: review.before, now: review.reviewedAt, settings: review.settingsSnapshot ?? settings)
    }
}
