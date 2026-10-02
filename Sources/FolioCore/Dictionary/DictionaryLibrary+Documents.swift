import Foundation
import GRDB

extension DictionaryLibrary {
    func documentsSnapshot(sourceID: String) throws -> DocumentsArchiveSnapshot? {
        try database.read { db in
            try Data.fetchOne(db, sql: "SELECT snapshot FROM managed_archives WHERE sourceID = ?", arguments: [sourceID])
                .map { try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: $0) }
        }
    }

    func synchronizeDocumentsArchive(_ snapshot: DocumentsArchiveSnapshot, root: URL) throws -> Bool {
        let previous = try database.read { db in
            try Data.fetchOne(db, sql: "SELECT snapshot FROM managed_archives WHERE stem = ?", arguments: [snapshot.stem])
                .map { try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: $0) }
        }
        guard previous != snapshot else { return false }
        return try ArchiveFileAccess.read(snapshot.urls(in: root)) {
            guard try snapshot.isCurrent(in: root) else { throw DocumentsDictionaryError.changingFile }
            try database.write { db in
                if previous?.mdx != snapshot.mdx {
                    // Rebuild entries and resources together; keep the source ID and user preferences.
                    try Self.importArchives(snapshot.urls(in: root), db: db)
                } else {
                    let id = try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ?", arguments: [snapshot.stem])
                    guard let id else { throw MDictError.missingDictionary }
                    try db.execute(sql: "DELETE FROM resources WHERE dictionaryID = ?", arguments: [id])
                    if let mdd = snapshot.mdd { try Self.importArchives([root.appendingPathComponent(mdd.filename)], db: db) }
                }
                try Task.checkCancellation()
                // Also protects against writers that don't participate in file coordination.
                guard try snapshot.isCurrent(in: root) else { throw DocumentsDictionaryError.changingFile }
                let id = try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ?", arguments: [snapshot.stem])
                guard let id else { throw MDictError.missingDictionary }
                try db.execute(sql: "INSERT OR REPLACE INTO managed_archives(stem, sourceID, snapshot) VALUES (?, ?, ?)",
                    arguments: [snapshot.stem, id, try JSONEncoder().encode(snapshot)])
            }
            return true
        }
    }

    func removeMissingDocumentsArchives(presentStems: Set<String>, root: URL) throws -> Int {
        try database.write { db in
            var removed = 0
            for row in try Row.fetchAll(db, sql: "SELECT stem, sourceID, snapshot FROM managed_archives") {
                let stem: String = row["stem"]
                guard !presentStems.contains(stem) else { continue }
                let snapshot = try JSONDecoder().decode(DocumentsArchiveSnapshot.self, from: row["snapshot"])
                // Recheck after the import queue: a Files copy may have completed since enumeration.
                guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(snapshot.mdx.filename).path) else { continue }
                try Task.checkCancellation()
                try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [row["sourceID"] as String])
                removed += 1
            }
            return removed
        }
    }
}
