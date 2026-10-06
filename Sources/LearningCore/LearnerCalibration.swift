import Foundation

public struct LearnerTrainingRow: Codable, Sendable {
    public let learnerID: String
    public let evidence: LearnerEvidence
    public init(learnerID: String, evidence: LearnerEvidence) { self.learnerID = learnerID; self.evidence = evidence }
}

/// These are explicit optimizer/evaluation policies, not learned model coefficients.
public struct LearnerFitOptions: Codable, Sendable {
    public var iterations = 500
    public var tolerance = 1e-5
    public var minimumTraining = 40
    public var minimumValidation = 20
    public var regularization = 0.1
    public var maximumCalibrationError = 0.2
    public var windows: [Double?] = [3600, 86400, 604800, 2592000, nil]
    public var abilityGrid = stride(from: -6.0, through: 6.0, by: 0.25).map { $0 }
    public init() {}
    public func validate() throws {
        guard (10...10000).contains(iterations), tolerance.isFinite, tolerance > 0,
              minimumTraining >= 2, minimumValidation >= 2, regularization.isFinite, regularization > 0,
              maximumCalibrationError.isFinite, (0...1).contains(maximumCalibrationError),
              !windows.isEmpty, windows.last! == nil, windows.compactMap({ $0 }).count == windows.count - 1,
              windows.compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 }),
              zip(windows.compactMap({ $0 }), windows.compactMap({ $0 }).dropFirst()).allSatisfy({ $0 < $1 }),
              (5...201).contains(abilityGrid.count), abilityGrid.allSatisfy(\.isFinite),
              zip(abilityGrid, abilityGrid.dropFirst()).allSatisfy({ $0 < $1 }) else { throw LearnerError.invalidEvidence }
    }
}

public struct LearnerCalibrationReport: Codable, Sendable {
    public struct Bin: Codable, Sendable {
        public let count: Int
        public let meanPrediction: Double
        public let observedCorrect: Double
    }
    public let id: String
    public let model: LearnerModelID
    public let trainingAttempts: Int
    public let validationAttempts: Int
    public let trainingLearners: Int
    public let validationLearners: Int
    public let converged: Bool
    public let logLoss: Double
    public let baselineLogLoss: Double
    public let brier: Double
    public let calibrationError: Double
    public let bins: [Bin]
    public let options: LearnerFitOptions
    public let splitDescription: String
    /// Exact accepted training/validation identities/revisions, never answer text.
    public let evidenceManifest: [String]
    public var eligibleForReview: Bool {
        converged && trainingAttempts >= options.minimumTraining && validationAttempts >= options.minimumValidation
            && logLoss.isFinite && logLoss <= baselineLogLoss && calibrationError <= options.maximumCalibrationError
    }
    public func validate() throws {
        try options.validate()
        guard !id.isEmpty, trainingAttempts > 0, validationAttempts > 0,
              trainingLearners > 0, validationLearners > 0,
              [logLoss, baselineLogLoss, brier, calibrationError].allSatisfy({ $0.isFinite && $0 >= 0 }),
              !splitDescription.isEmpty, evidenceManifest.count == trainingAttempts + validationAttempts,
              Set(evidenceManifest).count == evidenceManifest.count,
              bins.reduce(0, { $0 + $1.count }) == validationAttempts,
              bins.allSatisfy({ $0.count > 0 && (0...1).contains($0.meanPrediction) && (0...1).contains($0.observedCorrect) })
        else { throw LearnerError.invalidEvidence }
    }
}

/// Candidate artifacts persist with actual evaluation results. Review is a separate explicit action.
public struct LearnerCalibrationCandidate: Codable, Sendable {
    public let account: UUID
    public let library: String
    public let learnerID: String
    public let evidenceRevision: Int
    public let report: LearnerCalibrationReport
    public let parameters: Data
    public let sourceRevisions: [String: Int]
    public init(account: UUID, library: String, learnerID: String, evidenceRevision: Int,
                report: LearnerCalibrationReport, parameters: Data, sourceRevisions: [String: Int] = [:]) {
        self.account = account; self.library = library; self.learnerID = learnerID; self.evidenceRevision = evidenceRevision
        self.report = report; self.parameters = parameters
        self.sourceRevisions = sourceRevisions
    }
    public func predictor() throws -> any LearnerPredictor {
        try report.validate()
        let decoder = JSONDecoder(), predictor: any LearnerPredictor
        switch report.model {
        case .bkt: predictor = BKTLearnerPredictor(artifact: try decoder.decode(BKTLearnerPredictor.Artifact.self, from: parameters))
        case .das3h: predictor = DAS3HLearnerPredictor(artifact: try decoder.decode(DAS3HLearnerPredictor.Artifact.self, from: parameters))
        case .dynamicRasch: predictor = DynamicRaschLearnerPredictor(artifact: try decoder.decode(DynamicRaschLearnerPredictor.Artifact.self, from: parameters))
        case .dina: predictor = DINALearnerPredictor(artifact: try decoder.decode(DINALearnerPredictor.Artifact.self, from: parameters))
        }
        guard predictor.artifactRevision == report.id, predictor.readiness == nil else { throw LearnerError.invalidEvidence }
        return predictor
    }
}

enum LearnerOptimizer {
    /// Deterministic derivative-free coordinate search for small latent-model fits.
    /// Starts are optimization seeds only. Failed/non-converged fits remain ineligible.
    static func minimize(start: [Double], options: LearnerFitOptions, objective: ([Double]) throws -> Double) throws -> (values: [Double], converged: Bool) {
        var values = start, best = try objective(start), step = 1.0
        guard best.isFinite else { throw LearnerError.invalidEvidence }
        for _ in 0..<options.iterations {
            try Task.checkCancellation()
            var improved = false
            for index in values.indices {
                for direction in [-1.0, 1.0] {
                    var candidate = values; candidate[index] += direction * step
                    guard abs(candidate[index]) <= 20 else { continue }
                    let score = try objective(candidate)
                    if score.isFinite && score < best - options.tolerance * 0.01 {
                        values = candidate; best = score; improved = true
                    }
                }
            }
            if !improved { step *= 0.5 }
            if step < options.tolerance { return (values, true) }
        }
        return (values, false)
    }
}

public enum LearnerCalibration {
    /// Validation contains later timestamps per learner; DINA uses entirely held-out learners.
    /// Only explicitly permitted, accepted, unassisted binary observations may be submitted.
    public static func fit(model: LearnerModelID, training: [LearnerTrainingRow], validation: [LearnerTrainingRow],
                           targetLearner: String, account: UUID, library: String, evidenceRevision: Int,
                           options: LearnerFitOptions = LearnerFitOptions()) throws -> LearnerCalibrationCandidate {
        try options.validate()
        guard !targetLearner.isEmpty, evidenceRevision > 0, library == "default" || UUID(uuidString: library) != nil,
              training.count >= options.minimumTraining, validation.count >= options.minimumValidation,
              training.count + validation.count <= 20000 else { throw LearnerError.unavailable }
        var identities: Set<String> = []
        for row in training + validation {
            try row.evidence.validate()
            guard !row.learnerID.isEmpty, row.evidence.acceptance == .accepted, row.evidence.correct != nil,
                  row.evidence.assisted == false,
                  identities.insert("\(row.learnerID.utf8.count):\(row.learnerID)\(row.evidence.attemptID.utf8.count):\(row.evidence.attemptID)").inserted else { throw LearnerError.invalidEvidence }
        }
        let trainingByLearner = Dictionary(grouping: training, by: \.learnerID)
        let validationByLearner = Dictionary(grouping: validation, by: \.learnerID)
        if model == .dina {
            guard Set(trainingByLearner.keys).isDisjoint(with: Set(validationByLearner.keys)) else { throw LearnerError.invalidEvidence }
        } else {
            for (learner, rows) in validationByLearner {
                guard let prior = trainingByLearner[learner],
                      prior.map({ $0.evidence.occurredAt }).max()! < rows.map({ $0.evidence.occurredAt }).min()! else { throw LearnerError.invalidEvidence }
            }
        }
        let id = "fit-" + UUID().uuidString, parameters: Data, converged: Bool
        switch model {
        case .bkt: (parameters, converged) = try fitBKT(training, id: id, options: options)
        case .das3h: (parameters, converged) = try fitDAS3H(training, target: targetLearner, id: id, options: options)
        case .dynamicRasch: (parameters, converged) = try fitRasch(training, id: id, options: options)
        case .dina: (parameters, converged) = try fitDINA(training, id: id, options: options)
        }
        // Validation is prequential: predict each later answer before revealing its outcome.
        let predictions = try evaluate(model: model, parameters: parameters, training: training, validation: validation, target: targetLearner)
        let baseline = Double(training.filter { $0.evidence.correct == true }.count) / Double(training.count)
        let epsilon = 1e-12 // Numerical log safety only; not a fitted parameter.
        func loss(_ p: Double, _ correct: Bool) -> Double { -log(max(epsilon, min(1 - epsilon, correct ? p : 1 - p))) }
        var bins: [LearnerCalibrationReport.Bin] = []
        for bin in 0..<10 {
            let entries = predictions.filter { min(9, Int($0.0 * 10)) == bin }
            if !entries.isEmpty { bins.append(.init(count: entries.count, meanPrediction: entries.map(\.0).reduce(0, +) / Double(entries.count), observedCorrect: Double(entries.filter(\.1).count) / Double(entries.count))) }
        }
        let count = Double(predictions.count)
        let report = LearnerCalibrationReport(id: id, model: model, trainingAttempts: training.count,
            validationAttempts: predictions.count, trainingLearners: trainingByLearner.count, validationLearners: validationByLearner.count,
            converged: converged, logLoss: predictions.reduce(0) { $0 + loss($1.0, $1.1) } / count,
            baselineLogLoss: predictions.reduce(0) { $0 + loss(baseline, $1.1) } / count,
            brier: predictions.reduce(0) { $0 + pow($1.0 - ($1.1 ? 1 : 0), 2) } / count,
            calibrationError: bins.reduce(0) { $0 + Double($1.count) * abs($1.meanPrediction - $1.observedCorrect) } / count,
            bins: bins, options: options, splitDescription: model == .dina ? "Held-out learners; one assessment administration per learner" : "Later held-out timestamps per learner; predictions before outcomes",
            evidenceManifest: (training + validation).map(identity).sorted())
        try report.validate()
        return LearnerCalibrationCandidate(account: account, library: library.lowercased(), learnerID: targetLearner,
            evidenceRevision: evidenceRevision, report: report, parameters: parameters,
            sourceRevisions: Dictionary(uniqueKeysWithValues: (training + validation).filter { $0.learnerID == targetLearner }.map { ($0.evidence.attemptID, $0.evidence.revision) }))
    }
    private static func identity(_ row: LearnerTrainingRow) -> String {
        // Length prefixes prevent ambiguity in user-supplied IDs.
        "\(row.learnerID.utf8.count):\(row.learnerID)\(row.evidence.attemptID.utf8.count):\(row.evidence.attemptID):\(row.evidence.revision)"
    }
    static func mappingRevision(_ rows: [LearnerTrainingRow]) throws -> String {
        guard rows.allSatisfy({ $0.evidence.mapping != nil }), Set(rows.compactMap { $0.evidence.mapping?.revision }).count == 1 else { throw LearnerError.invalidEvidence }
        return rows[0].evidence.mapping!.revision
    }
}
