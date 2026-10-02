import Foundation
import CryptoKit
import LearningCore

/// Content-addressed owner-private blobs keep full documents out of shared rows and RPC limits.
enum PrivateCloudDocument {
    static func encode<T: Encodable>(_ record: T) throws -> Data {
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
    static func uploads(for entity: CloudProjectionEntity,library: LibrarySnapshot,userID: UUID) throws -> [(String,Data)] {
        guard entity.kind == "private",case .object(let envelope) = entity.payload,
              case .object(let extras) = envelope["value"] else { return [] }
        if envelope["category"] == .string("folderFiles"),
           case .string(let path) = extras["libraryDocumentsBlob"],let documents = library.folderDocuments {
            let data = try encode(documents)
            try validate(path:path,data:data,userID:userID)
            return [(path,data)]
        }
        guard envelope["category"] == .string("deckExtras"),case .string(let id) = envelope["id"],
              let deck = library.decks.first(where: { $0.id == id }) else { return [] }
        var result: [(String,Data)] = []
        if case .string(let path) = extras["pdfLearningBlob"],let record = deck.pdfLearning {
            result.append((path,try encode(record)))
        }
        if case .string(let path) = extras["libraryDocumentsBlob"],let documents = deck.documents {
            result.append((path,try encode(documents)))
        }
        for (path,data) in result { try validate(path:path,data:data,userID:userID) }
        return result
    }
    static func materialize(_ entity: CloudProjectionEntity,library: LibrarySnapshot,userID: UUID,client: any CloudTransport) async throws -> CloudProjectionEntity {
        guard entity.kind == "private",case .object(var envelope) = entity.payload,
              case .object(var extras) = envelope["value"] else { return entity }
        if envelope["category"] == .string("folderFiles") {
            if case .string(let path) = extras["libraryDocumentsBlob"] {
                let documents: [LibraryFolderDocument]
                if let existing = library.folderDocuments,try self.path(data:encode(existing),userID:userID) == path { documents = existing }
                else {
                    let bytes = try await client.downloadPrivateDocument(path:path)
                    try validate(path:path,data:bytes,userID:userID)
                    documents = try JSONDecoder().decode([LibraryFolderDocument].self,from:bytes)
                    for item in documents { try item.document.validate() }
                }
                extras["libraryDocuments"] = try .encode(documents)
            }
            envelope["value"] = .object(extras)
            var hydrated = entity; hydrated.payload = .object(envelope); return hydrated
        }
        guard envelope["category"] == .string("deckExtras") else { return entity }
        let local = CloudProjection.associatedDeck(entity).flatMap { id in library.decks.first(where: { $0.id == id }) }
        if case .string(let path) = extras["pdfLearningBlob"] {
            let record: PDFLearningRecord
            if let existing = local?.pdfLearning,try self.path(data:encode(existing),userID:userID) == path { record = existing }
            else {
                let bytes = try await client.downloadPrivateDocument(path:path)
                try validate(path:path,data:bytes,userID:userID)
                record = try JSONDecoder().decode(PDFLearningRecord.self,from:bytes)
                try record.source.validate(); try record.brief.validate(source:record.source)
            }
            extras["pdfLearning"] = try .encode(record)
        }
        if case .string(let path) = extras["libraryDocumentsBlob"] {
            let documents: [LibraryDocument]
            if let existing = local?.documents,try self.path(data:encode(existing),userID:userID) == path { documents = existing }
            else {
                let bytes = try await client.downloadPrivateDocument(path:path)
                try validate(path:path,data:bytes,userID:userID)
                documents = try JSONDecoder().decode([LibraryDocument].self,from:bytes)
                for document in documents { try document.validate() }
            }
            extras["libraryDocuments"] = try .encode(documents)
        }
        envelope["value"] = .object(extras)
        var hydrated = entity; hydrated.payload = .object(envelope); return hydrated
    }
}
