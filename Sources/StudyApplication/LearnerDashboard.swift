import Foundation
import LearningCore

/// Local observed outcomes only. Unknown assistance and partial/unclear grading are excluded.
/// No model ranking or causal inference can be derived from this projection.
public struct LearnerDashboard: Equatable, Sendable {
    public struct Outcome: Equatable, Sendable {
        public let correct: Int
        public let attempts: Int
        public var label: String { attempts == 0 ? "Insufficient evidence" : "\(correct) / \(attempts) observed correct" }
    }
    public let delayedRecall: Outcome
    public let unfamiliarQuestions: Outcome
    public let skillErrors: [String: Int]
    public let measuredStudySeconds: Double?
    public let timedAttempts: Int
    public let acceptedAttempts: Int
    public let comparison = "Insufficient evidence for learning comparisons"
    public init(state: LearnerState, minimumRecallDelay: Double = 86400) {
        self.init(evidence: state.latest, minimumRecallDelay: minimumRecallDelay)
    }
    public init(evidence: [LearnerEvidence], minimumRecallDelay: Double = 86400) {
        let accepted = evidence.filter { $0.acceptance == .accepted }
        let outcomes = accepted.filter { $0.assisted == false && $0.correct != nil }
        func summarize(_ rows: [LearnerEvidence]) -> Outcome {
            Outcome(correct: rows.filter { $0.correct == true }.count, attempts: rows.count)
        }
        delayedRecall = summarize(outcomes.filter { $0.kind == .recall && ($0.delaySeconds.map { $0 >= max(0, minimumRecallDelay) } ?? false) })
        unfamiliarQuestions = summarize(outcomes.filter { $0.kind != .recall && $0.unfamiliar == true })
        var errors: [String: Int] = [:]
        for row in outcomes where row.correct == false { for skill in row.errorSkillIDs { errors[skill, default: 0] += 1 } }
        skillErrors = errors
        let durations = accepted.compactMap(\.studySeconds)
        measuredStudySeconds = durations.isEmpty ? nil : durations.reduce(0, +)
        timedAttempts = durations.count; acceptedAttempts = accepted.count
    }
}

public struct LearnerModelDescription: Sendable {
    public let model: LearnerModelID
    public let purpose: String
    public let limitations: String
    public let evidenceStrength: String
    public let readiness: String
    public let selectable: Bool
    public static func catalog(predictors: [any LearnerPredictor], history: [LearnerEvidence]? = nil) -> [Self] {
        LearnerModelID.allCases.map { model in
            let adapter = predictors.first { $0.model == model }
            let hasHistory = history.map { rows in adapter.map { !$0.selectHistory(rows.filter($0.compatible)).isEmpty } ?? false } ?? true
            let description: (String, String)
            switch model {
            case .das3h: description = ("Predict skill performance from spaced practice", "Requires reviewed mappings, fitted coefficients and validation for this task.")
            case .bkt: description = ("Estimate skill mastery", "Single-skill implementation; no forgetting or difficulty model. Conditional point estimates omit parameter uncertainty.")
            case .dynamicRasch: description = ("Estimate changing learner ability against calibrated item difficulty", "Finite-grid one-dimensional approximation; uncertainty is conditional on fitted item/process parameters. Requires scale anchors and longitudinal validation.")
            case .dina: description = ("Diagnose supported assessment skill profiles", "Assessment-scoped inference; no learning transitions. Requires identifiable reviewed Q-matrix and calibration. Profile uncertainty is conditional on fixed parameters.")
            }
            return Self(model: model, purpose: description.0, limitations: description.1,
                evidenceStrength: "Model-family research is not evidence of personal learning superiority.",
                readiness: adapter?.readiness ?? (adapter == nil ? "Unavailable: no reviewed artifact installed." : !hasHistory ? "Insufficient compatible history; calibration artifact is present." : "Reviewed artifact and compatible history are available."),
                selectable: adapter != nil && adapter?.readiness == nil && hasHistory)
        }
    }
}
