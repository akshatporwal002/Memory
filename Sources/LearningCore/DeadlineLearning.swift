import Foundation

/// Independent, deliberately uncalibrated research baseline. Never reads or mutates FSRS state.
public struct DeadlineGoal: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var prompt: String
        public var answer: String
        public var questionType: String
        public var questionVersion: Int
        public init(id: String, prompt: String, answer: String, questionType: String, questionVersion: Int) {
            self.id = id; self.prompt = prompt; self.answer = answer; self.questionType = questionType; self.questionVersion = questionVersion
        }
    }
    public var deckID: String
    public var createdAt: Date
    public var deadline: Date
    public var target: Double
    public var dailyMinutes: Int
    public var items: [Item]
    public init(deckID: String, createdAt: Date, deadline: Date, target: Double, dailyMinutes: Int, items: [Item]) {
        self.deckID = deckID; self.createdAt = createdAt; self.deadline = deadline
        self.target = target; self.dailyMinutes = dailyMinutes; self.items = items
    }
    public func validate() throws {
        guard !deckID.isEmpty, createdAt.timeIntervalSince1970.isFinite, deadline.timeIntervalSince1970.isFinite,
              deadline > createdAt, deadline.timeIntervalSince(createdAt) <= 366 * 86400,
              target.isFinite, (0.1...0.99).contains(target), (1...120).contains(dailyMinutes),
              !items.isEmpty, items.count <= 500, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ !$0.id.isEmpty && !$0.prompt.isEmpty && !$0.answer.isEmpty && $0.questionVersion >= 0 }) else {
            throw EngramError.invalid("Choose a future deadline within one year, a target from 10–99%, and 1–120 minutes daily. A plan supports 1–500 cards.")
        }
    }
}

public struct DeadlinePlan: Codable, Equatable, Sendable {
    public struct Action: Codable, Equatable, Identifiable, Sendable {
        public var id: String { cardID + ":" + String(date.timeIntervalSince1970) }
        public var cardID: String
        public var date: Date
        public var seconds: Double
    }
    public let generatedAt: Date
    public let evidenceRevision: Int
    public let policyVersion: String
    public let baseline: Double
    public let forecast: Double
    public let observations: Int
    public let observedCorrect: Int
    public let timedSeconds: Double
    public let staleItems: Int
    public let actions: [Action]
    public var plannedMinutes: Int { Int(ceil(actions.reduce(0) { $0 + $1.seconds } / 60)) }
}

public enum DeadlinePlanner {
    private struct Memory {
        var probability: Double = 0.35
        var halfLife: Double = 86400
        var last: Date
        var seconds: Double = 60
        func recall(at date: Date) -> Double {
            probability * pow(2, -max(0, date.timeIntervalSince(last)) / halfLife)
        }
        func reviewed(at date: Date) -> Self {
            let p = recall(at: date)
            // Hypothesis, not a causal estimate: outcome-weighted retrieval benefit.
            return Self(probability: 0.65 + 0.35 * p, halfLife: min(366 * 86400, halfLife * (1 + 0.5 * p)), last: date, seconds: seconds)
        }
    }
    public static func make(goal: DeadlineGoal, evidence: [LearnerEvidence], evidenceRevision: Int,
                            staleItems: Int = 0, verifiedAttemptIDs: Set<String> = [], recentlyPractisedIDs: Set<String> = [], now: Date) throws -> DeadlinePlan {
        try goal.validate()
        guard now.timeIntervalSince1970.isFinite else { throw EngramError.invalid("Invalid planning date.") }
        let ids = Set(goal.items.map(\.id))
        // Retractions/corrections supersede previous revisions; do not leak future answers.
        var latest: [String: LearnerEvidence] = [:]
        for row in evidence where row.occurredAt <= now {
            if row.revision > (latest[row.attemptID]?.revision ?? 0) { latest[row.attemptID] = row }
        }
        let versions = Dictionary(uniqueKeysWithValues: goal.items.map { ($0.id, $0.questionVersion) })
        let rows = latest.values.filter { ids.contains($0.questionID) && (versions[$0.questionID] == $0.questionVersion || verifiedAttemptIDs.contains($0.attemptID)) && $0.acceptance == .accepted && $0.assisted == false && $0.correct != nil }
            .sorted { $0.occurredAt == $1.occurredAt ? $0.attemptID < $1.attemptID : $0.occurredAt < $1.occurredAt }
        var states = Dictionary(uniqueKeysWithValues: goal.items.map { ($0.id, Memory(last: now)) })
        for row in rows {
            var state = states[row.questionID]!
            if row.correct == true {
                state.halfLife = min(366 * 86400, max(state.halfLife, (row.delaySeconds ?? 0) / 2) * 1.5)
                state.probability = 0.95
            } else { state.halfLife = max(3600, state.halfLife * 0.5); state.probability = 0.45 }
            state.last = row.occurredAt
            if let seconds = row.studySeconds, seconds > 0 { state.seconds = min(600, max(15, seconds)) }
            states[row.questionID] = state
        }
        func score(_ states: [String: Memory]) -> Double { states.values.reduce(0) { $0 + $1.recall(at: goal.deadline) } / Double(states.count) }
        let baseline = score(states)
        let observedIDs = Set(rows.map(\.questionID))
        var actions: [DeadlinePlan.Action] = []
        // Daily greedy rollout; each item at most once per day. Rebuilt from real evidence each time.
        let days = max(0, min(366, Int(ceil(goal.deadline.timeIntervalSince(now) / 86400))))
        for day in 0..<days where score(states) < goal.target && actions.count < 2000 && staleItems == 0 {
            let date = now.addingTimeInterval(Double(day) * 86400)
            guard date < goal.deadline else { break }
            var remaining = Double(goal.dailyMinutes * 60)
            var selected = Set<String>()
            for _ in 0..<min(goal.items.count, 100) {
                guard actions.count < 2000 else { break }
                let candidates = states.keys.sorted().filter {
                    !selected.contains($0) && states[$0]!.seconds <= remaining &&
                    (day != 0 || !recentlyPractisedIDs.contains($0)) &&
                    (!observedIDs.contains($0) || date.timeIntervalSince(states[$0]!.last) >= 86400)
                }
                let best = candidates.max { left, right in
                    func gain(_ id: String) -> Double {
                        let state = states[id]!
                        return (state.reviewed(at: date).recall(at: goal.deadline) - state.recall(at: goal.deadline)) / state.seconds
                    }
                    let a = gain(left), b = gain(right)
                    return a == b ? left > right : a < b
                }
                guard let best else { break }
                let old = states[best]!, updated = old.reviewed(at: date)
                guard updated.recall(at: goal.deadline) > old.recall(at: goal.deadline) + 1e-12 else { break }
                states[best] = updated; selected.insert(best); remaining -= old.seconds
                actions.append(.init(cardID: best, date: date, seconds: old.seconds))
                if score(states) >= goal.target { break }
            }
        }
        return DeadlinePlan(generatedAt: now, evidenceRevision: evidenceRevision, policyVersion: "deadline-greedy-experimental-v1",
                            baseline: baseline, forecast: score(states), observations: rows.count,
                            observedCorrect: rows.filter { $0.correct == true }.count,
                            timedSeconds: rows.compactMap(\.studySeconds).reduce(0, +), staleItems: staleItems, actions: actions)
    }
}

public struct DeadlineRecord: Codable, Equatable, Sendable {
    public var goal: DeadlineGoal
    public var forecasts: [DeadlinePlan]
    public init(goal: DeadlineGoal, forecasts: [DeadlinePlan] = []) { self.goal = goal; self.forecasts = forecasts }
}
