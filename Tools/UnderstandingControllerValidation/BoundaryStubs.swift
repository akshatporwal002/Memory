// Compile-only platform shell substitutes. No provider calls or fake runtime is installed.
import Foundation
import LearningCore
import StudyApplication

@MainActor final class ShellAccount {
    var userID: UUID?
    var localProfileID: String?
}
@MainActor final class ShellConnection {}
@MainActor final class ShellMarker {
    var enabled = false
    var selectedModel = ""
    var chatModel = ""
    var catalog: [String] = []
    func gradingIdentity(_ connection: ShellConnection) -> String { "" }
    func loadModels(connection: ShellConnection) async {}
    func text(instructions: String, input: String, model: String, connection: ShellConnection, limit: Int) async throws -> String { "" }
}
@MainActor final class EngramModel {
    var testingScope: String?
    let cloud = ShellAccount()
    let chatGPT = ShellConnection()
    let aiMarker = ShellMarker()
    var understanding: UnderstandingController { fatalError("Compile-only shell") }
    var service: StudyService { fatalError("Compile-only shell") }
    var activeLibraryID = "default"
    var library = LibrarySnapshot()
    var busy = false
    var error: String?
}
