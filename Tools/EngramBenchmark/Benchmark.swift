import Foundation
import LearningCore
import StudyApplication
import PersistenceAdapters
import SchedulingAdapters
import AnkiAdapters

/// Explicit development tool. Uses isolated temporary synthetic libraries, never app data.
@main struct EngramBenchmark {
    struct Sample: Codable {
        var notes: Int
        var mediaBytes: Int
        var libraryBytes: Int
        var initialCommitMS: Double
        var reopenMS: Double
        var beginSessionMS: Double
        var revealMS: Double
        var gradeMS: Double
        var backupWriteMS: Double
        var backupReadMS: Double
        var backupBytes: Int
        var completeBackupEqual: Bool
        var durableGradeEqual: Bool
    }
    struct Report: Codable {
        var measuredAt: Date
        var operatingSystem: String
        var processorCount: Int
        var physicalMemoryBytes: UInt64
        var notes: String
        var samples: [Sample]
    }
    static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
    static func run(count: Int, mediaBytes: Int) async throws -> Sample {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Engram-benchmark-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("library.json"), archive = folder.appendingPathComponent("complete.engram")
        let now = Date(timeIntervalSince1970: 1_788_393_600)
        var library = LibrarySnapshot(); library.settings = StudySettings(timeZoneID: "Australia/Sydney")
        let deck = Deck(id: "benchmark", name: "Synthetic benchmark")
        library.decks = [deck]
        let state = try FSRSScheduler().initialState(now: now, settings: library.settings)
        for index in 0..<count {
            let note = Note(id: "note-\(index)", deckID: deck.id, kind: .basic,
                front: "Synthetic question \(index): explain this concept.",
                back: String(repeating: "Synthetic answer with Unicode café 日本語. ", count: 8), tags: ["benchmark"])
            library.notes.append(note)
            library.cards.append(StudyCard(id: "card-\(index)", noteID: note.id, deckID: deck.id, schedule: state))
        }
        if mediaBytes > 0 {
            // Deterministic pseudo-random bytes represent already-compressed attachments;
            // this is deliberately not a valid image or an image-decoding benchmark.
            var seed: UInt64 = 0x123456789ABCDEF
            let data = Data((0..<mediaBytes).map { _ -> UInt8 in
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return UInt8(truncatingIfNeeded: seed)
            })
            library.media = [MediaFile(name: "synthetic-attachment.bin", data: data)]
        }
        let repository = try AtomicFileRepository(url: location)
        var start = DispatchTime.now().uptimeNanoseconds
        try await repository.commit(library, expectedRevision: 0)
        let commit = milliseconds(since: start)
        start = DispatchTime.now().uptimeNanoseconds
        let reopened = try AtomicFileRepository(url: location)
        _ = try await reopened.read()
        let open = milliseconds(since: start)
        let service = StudyService(repository: reopened, scheduler: FSRSScheduler())
        start = DispatchTime.now().uptimeNanoseconds
        let session = try await service.startSession(deckID: deck.id, now: now)
        let begin = milliseconds(since: start)
        guard let item = session.current else { throw EngramError.invalid("Benchmark did not produce a due card") }
        start = DispatchTime.now().uptimeNanoseconds
        _ = try await service.reveal(sessionID: session.id, presentationID: item.presentationID, now: now)
        let reveal = milliseconds(since: start)
        start = DispatchTime.now().uptimeNanoseconds
        try await service.grade(sessionID: session.id, presentationID: item.presentationID, rating: .good, mutationID: "benchmark-grade", now: now)
        let grade = milliseconds(since: start)
        let saved = try await service.snapshot()
        let durable = try AtomicFileRepository(url: location)
        let durableValue = try await durable.read()
        start = DispatchTime.now().uptimeNanoseconds
        try NativeBackupAdapter.write(saved, to: archive)
        let backupWrite = milliseconds(since: start)
        start = DispatchTime.now().uptimeNanoseconds
        let restored = try NativeBackupAdapter.read(from: archive)
        let backupRead = milliseconds(since: start)
        guard restored == saved, durableValue == saved, saved.reviews.count == 1 else {
            throw EngramError.invalid("Benchmark fidelity check failed")
        }
        return Sample(notes: count, mediaBytes: mediaBytes, libraryBytes: try Data(contentsOf: location).count,
            initialCommitMS: commit, reopenMS: open, beginSessionMS: begin, revealMS: reveal, gradeMS: grade,
            backupWriteMS: backupWrite, backupReadMS: backupRead, backupBytes: try Data(contentsOf: archive).count,
            completeBackupEqual: restored == saved, durableGradeEqual: durableValue == saved)
    }
    static func main() async throws {
        var samples: [Sample] = []
        for count in [1_000, 10_000] {
            for mediaBytes in [0, 16 * 1_024 * 1_024] {
                samples.append(try await run(count: count, mediaBytes: mediaBytes))
            }
        }
        let info = ProcessInfo.processInfo
        let report = Report(measuredAt: Date(), operatingSystem: info.operatingSystemVersionString,
            processorCount: info.processorCount, physicalMemoryBytes: info.physicalMemory,
            notes: "One cold sample per synthetic case, release configuration required. Timings include production validation and atomic file work. Not an Apple UI, image decoding, memory high-water or worst-case benchmark.", samples: samples)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        if CommandLine.arguments.count > 1 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic) }
        print(String(decoding: data, as: UTF8.self))
    }
}
