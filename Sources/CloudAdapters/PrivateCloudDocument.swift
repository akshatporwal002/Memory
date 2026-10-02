import Foundation
import CryptoKit
import LearningCore

/// Content-addressed owner-private blobs keep full documents out of shared rows and RPC limits.
enum PrivateCloudDocument {
    static func encode(_ record: PDFLearningRecord) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(record)
        guard data.count <= 45_000_000 else { throw EngramError.invalid("Private document exceeds the current 45 MB storage limit.") }
        return data
    }
    static func path(data: Data,userID: UUID) -> String {
        userID.uuidString.lowercased() + "/" + SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() + ".json"
    }
    static func validatePath(_ path: String,userID: UUID) throws {
        let pieces = path.split(separator:"/",omittingEmptySubsequences:false)
        guard pieces.count == 2,pieces[0] == userID.uuidString.lowercased(),pieces[1].hasSuffix(".json"),pieces[1].count == 69,pieces[1].dropLast(5).allSatisfy(\.isHexDigit) else { throw EngramError.invalid("Private document scope mismatch.") }
    }
    static func validate(path: String,data: Data,userID: UUID) throws {
        try validatePath(path,userID:userID)
        guard data.count <= 45_000_000,self.path(data:data,userID:userID) == path else { throw EngramError.invalid("Private document failed integrity verification.") }
    }
    static func reference(in entity: CloudProjectionEntity) -> String? {
        guard entity.kind == "private",case .object(let envelope) = entity.payload,envelope["category"] == .string("deckExtras"),case .object(let extras) = envelope["value"],case .string(let path) = extras["pdfLearningBlob"] else { return nil }
        return path
    }
    static func materialize(_ entity: CloudProjectionEntity,library: LibrarySnapshot,userID: UUID,client: any CloudTransport) async throws -> CloudProjectionEntity {
        guard let path = reference(in:entity),case .object(var envelope) = entity.payload,case .object(var extras) = envelope["value"] else { return entity }
        try validatePath(path,userID:userID)
        let record: PDFLearningRecord
        if let id = CloudProjection.associatedDeck(entity),let local = library.decks.first(where: { $0.id == id })?.pdfLearning,try self.path(data:encode(local),userID:userID) == path { record = local }
        else {
            let bytes = try await client.downloadPrivateDocument(path:path)
            try validate(path:path,data:bytes,userID:userID)
            record = try JSONDecoder().decode(PDFLearningRecord.self,from:bytes)
            try record.source.validate(); try record.brief.validate(source:record.source)
        }
        extras["pdfLearning"] = try .encode(record); envelope["value"] = .object(extras)
        var hydrated = entity; hydrated.payload = .object(envelope); return hydrated
    }
}
