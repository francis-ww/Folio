import Foundation
import GRDB

extension DictionaryLibrary {
    func documentsSnapshots() throws -> [DocumentsArchiveSnapshot] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT snapshot FROM managed_archives")
                .map { try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: $0) }
        }
    }

    func documentsSnapshot(sourceID: String) throws -> DocumentsArchiveSnapshot? {
        try database.read { db in
            try Data.fetchOne(db, sql: "SELECT snapshot FROM managed_archives WHERE sourceID = ?", arguments: [sourceID])
                .map { try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: $0) }
        }
    }

    private func documentsSnapshot(stem: String) throws -> DocumentsArchiveSnapshot? {
        try database.read { db in
            try Data.fetchOne(db, sql: "SELECT snapshot FROM managed_archives WHERE stem = ?", arguments: [stem])
                .map { try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: $0) }
        }
    }

    func synchronizeDocumentsArchive(_ snapshot: DocumentsArchiveSnapshot, root: URL) async throws -> Bool {
        let definitions = try await synchronizeDocumentsDefinitions(snapshot, root: root)
        let resources = try await synchronizeDocumentsResources(snapshot, root: root)
        return definitions || resources
    }

    func synchronizeDocumentsDefinitions(_ snapshot: DocumentsArchiveSnapshot, root: URL) async throws -> Bool {
        let previous = try documentsSnapshot(stem: snapshot.stem)
        guard previous?.mdx != snapshot.mdx else { return false }
        let url = root.appendingPathComponent(snapshot.mdx.filename)
        guard try ArchiveFileStamp.read(url, root: root) == snapshot.mdx else { throw DocumentsDictionaryError.changingFile }
        // Publish usable definitions before indexing MDD. The prior resource index survives a failed update.
        let partial = DocumentsArchiveSnapshot(stem: snapshot.stem, mdx: snapshot.mdx, mdd: previous?.mdd)
        try await importArchives([url], preservingResources: true, stemOverride: snapshot.stem) { db in
            guard try ArchiveFileStamp.read(url, root: root) == snapshot.mdx else { throw DocumentsDictionaryError.changingFile }
            try Self.saveDocumentsSnapshot(partial, db: db)
        }
        return true
    }

    func synchronizeDocumentsResources(_ snapshot: DocumentsArchiveSnapshot, root: URL) async throws -> Bool {
        let previous = try documentsSnapshot(stem: snapshot.stem)
        guard previous?.mdd != snapshot.mdd else { return false }
        if let mdd = snapshot.mdd {
            let url = root.appendingPathComponent(mdd.filename)
            guard try ArchiveFileStamp.read(url, root: root) == mdd else { throw DocumentsDictionaryError.changingFile }
            try await importArchives([url], preservingResources: true, stemOverride: snapshot.stem) { db in
                guard try snapshot.isCurrent(in: root) else { throw DocumentsDictionaryError.changingFile }
                try Self.saveDocumentsSnapshot(snapshot, db: db)
            }
        } else {
            guard try snapshot.isCurrent(in: root) else { throw DocumentsDictionaryError.changingFile }
            let id = try withLibraryRead { db in try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ?", arguments: [snapshot.stem]) }
            guard let id else { throw MDictError.missingDictionary }
            let oldFiles = try withLibraryRead { db in try String.fetchAll(db, sql: "SELECT resourceIndex FROM sources WHERE id = ? AND resourceIndex IS NOT NULL", arguments: [id]) }
            try withLibraryWrite { db in
                try db.execute(sql: "DELETE FROM resources WHERE dictionaryID = ?", arguments: [id])
                try db.execute(sql: "UPDATE sources SET resourceIndex = NULL, indexedResources = 0 WHERE id = ?", arguments: [id])
                try Self.saveDocumentsSnapshot(snapshot, db: db)
            }
            removeIndexFiles(oldFiles)
        }
        return true
    }

    private static func saveDocumentsSnapshot(_ snapshot: DocumentsArchiveSnapshot, db: Database) throws {
        guard let id = try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ?", arguments: [snapshot.stem]) else { throw MDictError.missingDictionary }
        try db.execute(sql: "INSERT OR REPLACE INTO managed_archives(stem, sourceID, snapshot) VALUES (?, ?, ?)",
                       arguments: [snapshot.stem, id, try JSONEncoder().encode(snapshot)])
    }

    func removeMissingDocumentsArchives(presentStems: Set<String>, root: URL) throws -> Int {
        let rows = try database.read { db in try Row.fetchAll(db, sql: "SELECT stem, sourceID, snapshot FROM managed_archives") }
        var removed = 0
        for row in rows {
            guard !presentStems.contains(row["stem"]) else { continue }
            let snapshot = try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: row["snapshot"])
            guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.mdx.filename).path) else { continue }
            try Task.checkCancellation()
            try removeSource(id: row["sourceID"])
            removed += 1
        }
        return removed
    }
}
