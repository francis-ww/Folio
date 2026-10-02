import Foundation
import GRDB

extension DictionaryLibrary {
    func withLibraryRead<T>(_ body: (Database) throws -> T) throws -> T { try database.read(body) }
    func withLibraryWrite<T>(_ body: (Database) throws -> T) throws -> T { try database.write(body) }
    func indexFiles(sourceID: String) throws -> [String] {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT definitionIndex, resourceIndex FROM sources WHERE id = ?", arguments: [sourceID]) else { return [] }
            return [row["definitionIndex"] as String?, row["resourceIndex"] as String?].compactMap { $0 }
        }
    }

    func removeIndexFiles(_ files: [String]) {
        for filename in files {
            indexCache[filename] = nil
            guard filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".sqlite") else { continue }
            try? FileManager.default.removeItem(at: indexRoot.appendingPathComponent(filename))
        }
    }

    func definitionIndex(_ sourceID: String) throws -> MDictIndexDatabase? { try sourceIndex(sourceID, column: "definitionIndex") }
    func resourceIndex(_ sourceID: String) throws -> MDictIndexDatabase? { try sourceIndex(sourceID, column: "resourceIndex") }

    private func sourceIndex(_ sourceID: String, column: String) throws -> MDictIndexDatabase? {
        guard let filename = try database.read({ db in try String.fetchOne(db, sql: "SELECT \(column) FROM sources WHERE id = ?", arguments: [sourceID]) }) else { return nil }
        guard filename == URL(fileURLWithPath: filename).lastPathComponent, filename.hasSuffix(".sqlite") else { throw DocumentsDictionaryError.unsafeFile }
        if let cached = indexCache[filename] { return cached }
        let url = indexRoot.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { throw MDictError.malformed("missing dictionary index") }
        let index = try MDictIndexDatabase(url: url)
        indexCache[filename] = index
        return index
    }

    func indexedSourceIDs() throws -> [String] {
        try database.read { db in try String.fetchAll(db, sql: "SELECT id FROM sources WHERE definitionIndex IS NOT NULL") }
    }

    static func entry(id: String, database: DatabaseQueue) throws -> DictionaryEntry? {
        try database.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM entries WHERE id = ?", arguments: [id])
                .map { try JSONDecoder().decode(DictionaryEntry.self, from: $0) }
        }
    }

    static func searchIndex(_ query: String, index: MDictIndexDatabase) throws -> [DictionaryEntry] {
        try index.database.read { db in
            let rows: [Row]
            if query.isEmpty { rows = try Row.fetchAll(db, sql: "SELECT payload FROM entries ORDER BY headword LIMIT 30") }
            else {
                let tokens = query.split(whereSeparator: { $0.isWhitespace })
                let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
                rows = try Row.fetchAll(db, sql: """
                    SELECT e.payload FROM entries e JOIN entries_fts f ON f.rowid = e.rowid
                    WHERE entries_fts MATCH ? ORDER BY (e.headword = ? COLLATE NOCASE) DESC, length(e.headword), e.headword LIMIT 50
                    """, arguments: [match, query])
            }
            return try rows.map { try JSONDecoder().decode(DictionaryEntry.self, from: $0["payload"]) }
        }
    }
}
