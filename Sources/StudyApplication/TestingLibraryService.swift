import Foundation
import LearningCore

public struct TestingLibraryImport: Sendable {
    public let addedDecks: Int
    public let addedQuestions: Int
    public let preservedQuestions: Int
}

/// Original practice content, not an exam dump. Existing question formats only.
public enum TestingLibraryContent {
    public struct Question: Sendable {
        public let key: String
        public let front: String
        public let back: String
        public let source: String
    }
    public struct SampleDeck: Sendable {
        public let key: String
        public let name: String
        public let questions: [Question]
    }
    private static let responsibility = "https://aws.amazon.com/compliance/shared-responsibility-model/"
    private static let front = "https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/Introduction.html"
    private static let watch = "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html"
    private static let trail = "https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html"
    public static let decks: [SampleDeck] = [
        SampleDeck(key: "aws-mcq", name: "AWS · Multiple choice", questions: [
            Question(key: "edge", front: "Which service delivers web content through edge locations?\nA) Amazon CloudFront\nB) AWS CloudTrail\nC) Amazon CloudWatch\nD) Amazon EC2",
                back: "A) Amazon CloudFront\nCloudFront delivers content from edge locations near viewers to reduce latency.", source: front),
            Question(key: "patch", front: "Under the shared responsibility model, who patches the guest operating system on an Amazon EC2 instance?\nA) AWS always patches it for you\nB) The customer\nC) The internet service provider\nD) The customer has no responsibility for guest operating systems",
                back: "B) The customer\nFor EC2, the customer manages the guest operating system, including updates and security patches.", source: responsibility),
            Question(key: "alarm", front: "Which service provides metrics and alarms for monitoring AWS resources?\nA) AWS CloudTrail\nB) Amazon CloudFront\nC) Amazon CloudWatch\nD) AWS Identity and Access Management",
                back: "C) Amazon CloudWatch\nCloudWatch provides metrics and threshold alarms for operational monitoring.", source: watch),
            Question(key: "long", front: "A learning platform serves static lesson images to students around the world. Its existing origin contains the definitive files, but learners far from the origin experience delays. The team wants to cache content near viewers without treating an audit log or monitoring dashboard as a content-delivery service. Which option best meets this requirement?\nA) Use AWS CloudTrail to record requests and deliver cached images from audit events\nB) Use Amazon CloudFront with the existing server as an origin and deliver cached content from edge locations\nC) Use a CloudWatch alarm as the content origin so it can return lesson images\nD) Move every student to the same physical location as the origin server",
                back: "B) Use Amazon CloudFront with the existing server as an origin and deliver cached content from edge locations\nCloudFront uses origins and edge locations to deliver content with lower latency.", source: front)
        ]),
        SampleDeck(key: "aws-recall", name: "AWS · Short answer", questions: [
            Question(key: "edge", front: "How does CloudFront reduce content-delivery latency?", back: "It caches and delivers content at edge locations near viewers.", source: front),
            Question(key: "origin", front: "What is an origin in a CloudFront distribution?", back: "The source that holds the definitive content, such as an S3 bucket or HTTP server.", source: front),
            Question(key: "patch", front: "For EC2, who manages guest operating-system security patches?", back: "The customer manages guest operating-system updates and security patches.", source: responsibility),
            Question(key: "boundary", front: "Does AWS manage the guest operating system on a customer's EC2 instance? Explain the responsibility boundary.", back: "No. AWS protects the underlying cloud infrastructure; the customer manages the EC2 guest operating system.", source: responsibility),
            Question(key: "monitor", front: "What would you use to monitor a metric and alert when it exceeds a threshold?", back: "A CloudWatch alarm monitors the metric against a configured threshold and can alert when it is breached.", source: watch),
            Question(key: "audit", front: "What is the main purpose of AWS CloudTrail?", back: "CloudTrail records activity in an AWS account for auditing and investigation.", source: trail)
        ]),
        SampleDeck(key: "math-input", name: "Maths · Text input", questions: [
            Question(key: "fraction", front: "Write one half using mathematical notation.", back: "\\(\\frac{1}{2}\\)", source: "Engram original notation exercise. Existing text-answer card; manual rating when equivalence is not supported."),
            Question(key: "integral", front: "Write the definite integral of x squared from 0 to 1. You do not need to evaluate it.", back: "\\(\\int_0^1 x^2\\,dx\\)", source: "Engram original notation exercise. Input only; no symbolic solver."),
            Question(key: "binomial", front: "Write the probability mass function for X following a binomial distribution with parameters n and p.", back: "\\(P(X=k)=\\binom{n}{k}p^k(1-p)^{n-k}\\), for integers k from 0 through n.", source: "Engram original mathematical notation exercise; assumes independent Bernoulli trials with common success probability p.")
        ])
    ]
}

extension StudyService {
    /// One versioned repository transaction, also used by ordinary sync. A sample
    /// identity is scoped to the selected library, so copies on separate libraries
    /// do not accidentally share scheduling or content IDs.
    public func importTestingLibrary(now: Date = Date()) async throws -> TestingLibraryImport {
        var library = try await repository.read()
        let scope = await libraries.selectedID
        var addedDecks = 0, addedQuestions = 0, preserved = 0
        for sample in TestingLibraryContent.decks {
            let deckID = "engram-testing-v1-" + scope + "-" + sample.key
            if library.decks.contains(where: { $0.id == deckID && $0.deleted }) {
                preserved += sample.questions.count; continue
            }
            if !library.decks.contains(where: { $0.id == deckID }) {
                let name = "Testing::" + sample.name
                guard !library.liveDecks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    throw EngramError.invalid("A notebook named \(name) already exists. Rename it before importing the testing samples.")
                }
                var deck = Deck(id: deckID, name: name, createdAt: now, modifiedAt: now)
                deck.sourceDocument = "Original practice questions for testing Engram. Not official AWS exam material.\n\n" + sample.questions.map { "## " + $0.front + "\n\n" + $0.back + "\n\nReference: " + $0.source }.joined(separator: "\n\n")
                library.decks.append(deck); addedDecks += 1
            }
            for question in sample.questions {
                let noteID = deckID + "-" + question.key
                guard !library.notes.contains(where: { $0.id == noteID }) else { preserved += 1; continue }
                let cardID = noteID + "-card"
                guard !library.cards.contains(where: { $0.id == cardID }) else { throw EngramError.conflict }
                let note = Note(id: noteID, deckID: deckID, kind: .basic, front: question.front, back: question.back,
                    tags: ["engram-testing-v1"], source: question.source, modifiedAt: now)
                let schedule = try scheduler.initialState(now: now, settings: library.settings)
                library.notes.append(note)
                library.cards.append(StudyCard(id: cardID, noteID: noteID, deckID: deckID, schedule: schedule))
                addedQuestions += 1
            }
        }
        if addedDecks > 0 || addedQuestions > 0 {
            if !(library.folders ?? []).contains(where: { $0.caseInsensitiveCompare("Testing") == .orderedSame }) {
                library.folders = (library.folders ?? []) + ["Testing"]
            }
            try LibraryValidation.validate(library)
            try Task.checkCancellation(); try await repository.commit(library, expectedRevision: library.revision)
        }
        return TestingLibraryImport(addedDecks: addedDecks, addedQuestions: addedQuestions, preservedQuestions: preserved)
    }
}
