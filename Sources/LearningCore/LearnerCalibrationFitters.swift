import Foundation

extension LearnerCalibration {
    static func fitBKT(_ rows: [LearnerTrainingRow], id: String, options: LearnerFitOptions) throws -> (Data, Bool) {
        let revision = try mappingRevision(rows)
        guard rows.allSatisfy({ $0.evidence.mapping?.skillIDs.count == 1 }) else { throw LearnerError.invalidEvidence }
        let bySkill = Dictionary(grouping: rows) { $0.evidence.mapping!.skillIDs[0] }
        var fitted: [String: BKTLearnerPredictor.Parameters] = [:], converged = true
        for (skill, records) in bySkill.sorted(by: { $0.key < $1.key }) {
            guard Set(records.map { $0.evidence.correct! }).count == 2 else { throw LearnerError.unavailable }
            let sequences = try Dictionary(grouping: records, by: \.learnerID).values.map { try LearnerMath.ordered($0.map(\.evidence)) }
            guard sequences.contains(where: { $0.count >= 3 }) else { throw LearnerError.unavailable }
            func parameters(_ x: [Double]) -> BKTLearnerPredictor.Parameters {
                let guess = LearnerMath.logistic(x[2])
                return .init(prior: LearnerMath.logistic(x[0]), learn: LearnerMath.logistic(x[1]),
                    guess: guess, slip: (1 - guess) * LearnerMath.logistic(x[3]))
            }
            func objective(_ x: [Double]) -> Double {
                let p = parameters(x)
                var loss = options.regularization * x.reduce(0) { $0 + $1 * $1 } / 2
                for sequence in sequences {
                    var learned = p.prior
                    for row in sequence {
                        let a = row.correct == true ? 1 - p.slip : p.slip
                        let b = row.correct == true ? p.guess : 1 - p.guess
                        let probability = learned * a + (1 - learned) * b
                        loss -= log(max(1e-12, probability))
                        let posterior = learned * a / max(1e-12, probability)
                        learned = posterior + (1 - posterior) * p.learn
                    }
                }
                return loss
            }
            // Multiple optimizer starts reduce local-solution sensitivity; no seed is used for production inference.
            var best: (values: [Double], converged: Bool)?
            var bestLoss = Double.infinity
            for start in [[0.0, -2, -1.5, -2], [-1.5, -3, -2, -1], [1, -1.5, -2, -2]] {
                let result = try LearnerOptimizer.minimize(start: start, options: options, objective: objective)
                let loss = objective(result.values)
                if loss < bestLoss { best = result; bestLoss = loss }
            }
            fitted[skill] = parameters(best!.values); converged = converged && best!.converged
        }
        return (try JSONEncoder().encode(BKTLearnerPredictor.Artifact(revision: id, mappingRevision: revision,
            trainingReport: id, heldOutValidationReport: id, parameters: fitted)), converged)
    }

    static func fitDAS3H(_ rows: [LearnerTrainingRow], target: String, id: String, options: LearnerFitOptions) throws -> (Data, Bool) {
        // Current artifact contains one personal ability coefficient; never reuse it for another learner.
        guard rows.allSatisfy({ $0.learnerID == target }), Set(rows.map { $0.evidence.correct! }).count == 2 else { throw LearnerError.unavailable }
        let revision = try mappingRevision(rows)
        let evidence = try LearnerMath.ordered(rows.map(\.evidence))
        let skills = Array(Set(evidence.flatMap { $0.mapping!.skillIDs })).sorted()
        let items = uniqueItems(evidence)
        let block = 1 + options.windows.count * 2, dimension = 1 + items.count + skills.count * block
        guard dimension <= 2000 else { throw LearnerError.unavailable }
        var features: [[(Int, Double)]] = [], outcomes: [Double] = []
        for row in evidence {
            let itemIndex = items.firstIndex { $0.questionID == row.questionID && $0.questionVersion == row.questionVersion }!
            var feature: [(Int, Double)] = [(0, 1), (1 + itemIndex, -1)]
            for skill in row.mapping!.skillIDs {
                let offset = 1 + items.count + skills.firstIndex(of: skill)! * block
                feature.append((offset, 1))
                let previous = evidence.filter { $0.occurredAt < row.occurredAt && $0.mapping!.skillIDs.contains(skill) }
                for (w, window) in options.windows.enumerated() {
                    let included = previous.filter { previous in window.map { row.occurredAt.timeIntervalSince(previous.occurredAt) <= $0 } ?? true }
                    feature.append((offset + 1 + 2 * w, log1p(Double(included.filter { $0.correct == true }.count))))
                    feature.append((offset + 2 + 2 * w, -log1p(Double(included.count))))
                }
            }
            features.append(feature); outcomes.append(row.correct == true ? 1 : 0)
        }
        func lossGradient(_ values: [Double]) -> (Double, [Double]) {
            var loss = options.regularization * values.reduce(0) { $0 + $1 * $1 } / 2
            var gradient = values.map { options.regularization * $0 }
            for (index, feature) in features.enumerated() {
                let logit = feature.reduce(0) { $0 + values[$1.0] * $1.1 }
                loss += max(logit, 0) + log1p(exp(-abs(logit))) - outcomes[index] * logit
                let residual = LearnerMath.logistic(logit) - outcomes[index]
                for (position, value) in feature { gradient[position] += residual * value }
            }
            return (loss, gradient)
        }
        var values = Array(repeating: 0.0, count: dimension), converged = false
        for _ in 0..<options.iterations {
            try Task.checkCancellation()
            let (loss, gradient) = lossGradient(values), norm = gradient.reduce(0) { $0 + $1 * $1 }
            if sqrt(norm) < options.tolerance { converged = true; break }
            var step = 1.0, accepted = false
            while step > 1e-12 {
                let candidate = zip(values, gradient).map { $0 - step * $1 }
                if lossGradient(candidate).0 <= loss - 1e-4 * step * norm {
                    values = candidate; accepted = true; break
                }
                step *= 0.5
            }
            if !accepted { break }
        }
        var coefficients: [String: DAS3HLearnerPredictor.Skill] = [:]
        for (index, skill) in skills.enumerated() {
            let offset = 1 + items.count + index * block
            coefficients[skill] = .init(easiness: values[offset], wins: options.windows.indices.map { values[offset + 1 + 2 * $0] }, attempts: options.windows.indices.map { values[offset + 2 + 2 * $0] })
        }
        let difficulties = items.enumerated().map { index, item in DAS3HLearnerPredictor.Item(questionID: item.questionID, questionVersion: item.questionVersion, difficulty: values[1 + index]) }
        return (try JSONEncoder().encode(DAS3HLearnerPredictor.Artifact(revision: id, mappingRevision: revision,
            trainingReport: id, heldOutValidationReport: id, ability: values[0], windows: options.windows, skills: coefficients, items: difficulties)), converged)
    }

    static func fitRasch(_ rows: [LearnerTrainingRow], id: String, options: LearnerFitOptions) throws -> (Data, Bool) {
        let items = uniqueItems(rows.map(\.evidence)), learners = Array(Set(rows.map(\.learnerID)))
        guard items.count >= 2, items.count <= 50 else { throw LearnerError.unavailable }
        // Connected learner/item design and response variation are required, not inferred item anchors.
        var reachedLearners: Set<String> = [learners.sorted()[0]], reachedItems: Set<String> = []
        for _ in 0..<(learners.count + items.count) {
            for row in rows {
                let key = itemKey(row.evidence)
                if reachedLearners.contains(row.learnerID) { reachedItems.insert(key) }
                if reachedItems.contains(key) { reachedLearners.insert(row.learnerID) }
            }
        }
        guard reachedLearners.count == learners.count, reachedItems.count == items.count else { throw LearnerError.unavailable }
        for item in items {
            let answers = rows.filter { $0.evidence.questionID == item.questionID && $0.evidence.questionVersion == item.questionVersion }
            guard answers.count >= 3, Set(answers.map { $0.evidence.correct! }).count == 2 else { throw LearnerError.unavailable }
        }
        let sequences = try Dictionary(grouping: rows, by: \.learnerID).values.map { try LearnerMath.ordered($0.map(\.evidence)) }
        guard sequences.contains(where: { Set($0.map(\.occurredAt)).count >= 3 }) else { throw LearnerError.unavailable }
        func artifact(_ values: [Double], staticVariance: Bool = false) throws -> DynamicRaschLearnerPredictor.Artifact {
            let sigma = exp(values[1])
            let prior = try LearnerMath.normalized(options.abilityGrid.map { -pow(($0 - values[0]) / sigma, 2) / 2 })
            let calibrated = items.enumerated().map { index, item in DAS3HLearnerPredictor.Item(questionID: item.questionID, questionVersion: item.questionVersion, difficulty: index == 0 ? 0 : values[2 + index]) }
            return .init(revision: id, trainingReport: id, heldOutValidationReport: id,
                scaleAnchor: "\(items[0].questionID)@\(items[0].questionVersion): difficulty zero is a scale convention, not a known empirical difficulty",
                grid: options.abilityGrid, prior: prior, variancePerDay: staticVariance ? 0 : exp(values[2]), items: calibrated)
        }
        func objective(_ values: [Double], staticVariance: Bool = false) throws -> Double {
            let fitted = try artifact(values, staticVariance: staticVariance), predictor = DynamicRaschLearnerPredictor(artifact: fitted)
            var loss = options.regularization * (values[0] * values[0] + values[1] * values[1] + values.dropFirst(3).reduce(0) { $0 + $1 * $1 }) / 2
            for sequence in sequences {
                var posterior = predictor.startingPosterior(at: sequence[0].occurredAt)
                for row in sequence {
                    let payload = try JSONEncoder().encode(posterior)
                    let p = try predictor.probability(questionID: row.questionID, questionVersion: row.questionVersion, at: row.occurredAt, history: payload)
                    loss -= log(max(1e-12, row.correct == true ? p : 1 - p))
                    posterior = try predictor.observe(row, prior: posterior)
                }
            }
            return loss
        }
        let start = [0.0, 0, -2] + Array(repeating: 0.0, count: items.count - 1)
        let dynamic = try LearnerOptimizer.minimize(start: start, options: options) { try objective($0) }
        let stationary = try LearnerOptimizer.minimize(start: start, options: options) { try objective($0, staticVariance: true) }
        let useStatic = try objective(stationary.values, staticVariance: true) <= objective(dynamic.values)
        let chosen = useStatic ? stationary : dynamic
        return (try JSONEncoder().encode(artifact(chosen.values, staticVariance: useStatic)), chosen.converged)
    }

    static func fitDINA(_ rows: [LearnerTrainingRow], id: String, options: LearnerFitOptions) throws -> (Data, Bool) {
        _ = try mappingRevision(rows)
        guard Set(rows.compactMap { $0.evidence.assessmentID }).count == 1,
              rows.allSatisfy({ $0.evidence.assessmentID?.isEmpty == false && $0.evidence.assessmentSessionID?.isEmpty == false }) else { throw LearnerError.invalidEvidence }
        let items = uniqueItems(rows.map(\.evidence))
        guard Set(items.map(\.questionID)).count == items.count else { throw LearnerError.invalidEvidence }
        let mappings = try items.map { item -> ReviewedSkillMapping in
            let found = rows.filter { $0.evidence.questionID == item.questionID && $0.evidence.questionVersion == item.questionVersion }.map { $0.evidence.mapping! }
            guard found.allSatisfy({ $0 == found[0] }) else { throw LearnerError.invalidEvidence }
            return found[0]
        }
        let skills = Array(Set(mappings.flatMap(\.skillIDs))).sorted(), sequences = Dictionary(grouping: rows, by: \.learnerID).values.map { $0.map(\.evidence) }
        guard (1...8).contains(skills.count), sequences.count >= 1 << skills.count,
              DINALearnerPredictor.identifiable(skillIDs: skills, mappings: mappings) else { throw LearnerError.unavailable }
        for sequence in sequences {
            guard Set(sequence.compactMap(\.assessmentSessionID)).count == 1, sequence.count == items.count,
                  Set(sequence.map(\.questionID)).count == items.count else { throw LearnerError.unavailable }
        }
        let profiles = 1 << skills.count
        let eta = mappings.map { mapping in (0..<profiles).map { profile in mapping.skillIDs.allSatisfy { profile & (1 << skills.firstIndex(of: $0)!) != 0 } } }
        var prior = Array(repeating: 1.0 / Double(profiles), count: profiles)
        var guesses = Array(repeating: 0.2, count: items.count), slips = Array(repeating: 0.1, count: items.count)
        var converged = false
        for _ in 0..<options.iterations {
            try Task.checkCancellation()
            var totals = Array(repeating: 0.0, count: profiles)
            var mastered = Array(repeating: 0.0, count: items.count), unmastered = mastered, missed = mastered, guessed = mastered
            for sequence in sequences {
                let byID = Dictionary(uniqueKeysWithValues: sequence.map { ($0.questionID, $0.correct!) })
                var logs = prior.map(log)
                for j in items.indices {
                    let correct = byID[items[j].questionID]!
                    for profile in 0..<profiles {
                        let p = eta[j][profile] ? 1 - slips[j] : guesses[j]
                        logs[profile] += log(correct ? p : 1 - p)
                    }
                }
                let posterior = try LearnerMath.normalized(logs)
                for profile in 0..<profiles { totals[profile] += posterior[profile] }
                for j in items.indices {
                    let mastery = posterior.indices.filter { eta[j][$0] }.reduce(0) { $0 + posterior[$1] }
                    mastered[j] += mastery; unmastered[j] += 1 - mastery
                    if byID[items[j].questionID]! { guessed[j] += 1 - mastery } else { missed[j] += mastery }
                }
            }
            let alpha = options.regularization
            let newPrior = totals.map { ($0 + alpha) / (Double(sequences.count) + Double(profiles) * alpha) }
            let newGuesses = items.indices.map { (guessed[$0] + alpha) / (unmastered[$0] + 2 * alpha) }
            let newSlips = items.indices.map { (missed[$0] + alpha) / (mastered[$0] + 2 * alpha) }
            // Refuse non-discriminating/boundary solutions instead of inventing usable diagnostics.
            guard zip(newGuesses, newSlips).allSatisfy({ $0 + $1 < 1 }) else { throw LearnerError.unavailable }
            let change = zip(prior + guesses + slips, newPrior + newGuesses + newSlips).map { abs($0 - $1) }.max()!
            prior = newPrior; guesses = newGuesses; slips = newSlips
            if change < options.tolerance { converged = true; break }
        }
        let calibrated = items.indices.map { DINALearnerPredictor.Item(mapping: mappings[$0], slip: slips[$0], guess: guesses[$0]) }
        return (try JSONEncoder().encode(DINALearnerPredictor.Artifact(revision: id, assessmentID: rows[0].evidence.assessmentID!,
            trainingReport: id, heldOutValidationReport: id, skillIDs: skills, profilePrior: prior, items: calibrated)), converged)
    }

    static func uniqueItems(_ evidence: [LearnerEvidence]) -> [DAS3HLearnerPredictor.Item] {
        var result: [DAS3HLearnerPredictor.Item] = []
        for row in evidence.sorted(by: { $0.questionID == $1.questionID ? $0.questionVersion < $1.questionVersion : $0.questionID < $1.questionID }) {
            if !result.contains(where: { $0.questionID == row.questionID && $0.questionVersion == row.questionVersion }) {
                result.append(.init(questionID: row.questionID, questionVersion: row.questionVersion, difficulty: 0))
            }
        }
        return result
    }
    static func itemKey(_ evidence: LearnerEvidence) -> String { "\(evidence.questionID.utf8.count):\(evidence.questionID):\(evidence.questionVersion)" }
}
