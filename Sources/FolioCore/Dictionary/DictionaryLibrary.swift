import Foundation
import GRDB

/// All archive I/O, decompression, and indexing stays on this actor's executor.
/// Only immutable Sendable values cross back into the UI.
public actor DictionaryLibrary: DictionaryRepository {
    private let database: DatabaseQueue

    public init(path: String) throws {
        let queue = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("library-v1") { db in
            try db.execute(sql: """
                CREATE TABLE sources (
                    id TEXT PRIMARY KEY, title TEXT NOT NULL, filename TEXT NOT NULL UNIQUE,
                    isSample INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE entries (
                    rowid INTEGER PRIMARY KEY, id TEXT NOT NULL UNIQUE,
                    dictionaryID TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    headword TEXT NOT NULL COLLATE NOCASE, payload BLOB NOT NULL
                );
                CREATE INDEX entries_headword ON entries(headword, dictionaryID);
                CREATE VIRTUAL TABLE entries_fts USING fts5(headword, tokenize='unicode61 remove_diacritics 2');
                CREATE TRIGGER entries_delete AFTER DELETE ON entries BEGIN
                    DELETE FROM entries_fts WHERE rowid = old.rowid;
                END;
                CREATE TABLE resources (
                    dictionaryID TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    path TEXT NOT NULL, payload BLOB NOT NULL,
                    PRIMARY KEY (dictionaryID, path)
                );
                """)
        }
        try migrator.migrate(queue)
        database = queue
    }

    public func seedSamples() throws {
        try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM sources WHERE id = 'folio-sample')") != true else { return }
            try db.execute(sql: "INSERT INTO sources(id, title, filename, isSample) VALUES (?, ?, ?, 1)",
                           arguments: ["folio-sample", "Folio sample dictionary", "sample"])
            for entry in SampleData.entries { try Self.insert(entry, db: db) }
        }
    }

    public func search(_ query: String) throws -> [DictionaryEntry] {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        return try database.read { db in
            let rows: [Row]
            if trimmed.isEmpty {
                rows = try Row.fetchAll(db, sql: "SELECT payload FROM entries ORDER BY headword LIMIT 30")
            } else {
                // Quote each token so user input cannot become an FTS operator.
                let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
                let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
                rows = try Row.fetchAll(db, sql: """
                    SELECT e.payload FROM entries e JOIN entries_fts f ON f.rowid = e.rowid
                    WHERE entries_fts MATCH ?
                    ORDER BY (e.headword = ? COLLATE NOCASE) DESC, length(e.headword), e.headword LIMIT 50
                    """, arguments: [match, trimmed])
            }
            return try rows.map { try JSONDecoder().decode(DictionaryEntry.self, from: $0["payload"]) }
        }
    }

    public func entry(id: String) throws -> DictionaryEntry? {
        try database.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM entries WHERE id = ?", arguments: [id]) else { return nil }
            return try JSONDecoder().decode(DictionaryEntry.self, from: data)
        }
    }

    public func lookup(_ headword: String, dictionaryID: String) throws -> DictionaryEntry? {
        try database.read { db in
            var target = headword
            var visited: Set<String> = []
            for _ in 0 ..< 12 {
                guard visited.insert(target.lowercased()).inserted,
                      let data = try Data.fetchOne(db, sql: "SELECT payload FROM entries WHERE headword = ? AND dictionaryID = ? LIMIT 1",
                                                  arguments: [target, dictionaryID]) else { return nil }
                let value = try JSONDecoder().decode(DictionaryEntry.self, from: data)
                if value.html.hasPrefix("@@@LINK=") {
                    target = String(value.html.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else { return value }
            }
            throw MDictError.malformed("dictionary link cycle")
        }
    }

    public func sources() throws -> [DictionarySource] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.*, (SELECT count(*) FROM entries WHERE dictionaryID = s.id) AS entryCount,
                    (SELECT count(*) FROM resources WHERE dictionaryID = s.id) AS resourceCount
                FROM sources s ORDER BY isSample, title
                """).map {
                    DictionarySource(id: $0["id"], title: $0["title"], filename: $0["filename"],
                                     entryCount: $0["entryCount"], resourceCount: $0["resourceCount"], isSample: $0["isSample"])
                }
        }
    }

    public func resource(path: String, dictionaryID: String) throws -> Data? {
        guard let key = ResourcePath.normalize(path) else { return nil }
        return try database.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM resources WHERE dictionaryID = ? AND path = ?", arguments: [dictionaryID, key])
        }
    }

    /// A selected MDX and matching MDD set commits together, or rolls back together.
    public func importArchives(_ urls: [URL]) throws {
        try Task.checkCancellation()
        let ordered = urls.sorted { $0.pathExtension.lowercased() == "mdx" && $1.pathExtension.lowercased() != "mdx" }
        try database.write { db in
            for url in ordered {
                try Task.checkCancellation()
                let ext = url.pathExtension.lowercased()
                guard ext == "mdx" || ext == "mdd" else { throw MDictError.unsupported("the .\(ext) file type") }
                let reader = try MDictReader(url: url, resourceArchive: ext == "mdd")
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                if ext == "mdx" {
                    let existing = try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ?", arguments: [stem])
                    if let existing {
                        try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [existing])
                    }
                    let id = existing ?? UUID().uuidString.lowercased()
                    try db.execute(sql: "INSERT INTO sources(id, title, filename) VALUES (?, ?, ?)", arguments: [id, reader.header.title, stem])
                    var number = 0
                    try reader.records { headword, raw in
                        guard let html = String(data: raw, encoding: reader.header.encoding) else { throw MDictError.malformed("definition encoding") }
                        let cleaned = html.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
                        let entry = DictionaryEntry(id: "\(id):\(number)", dictionaryID: id, headword: headword,
                                                    summary: Self.summary(cleaned), html: cleaned)
                        try Self.insert(entry, db: db)
                        number += 1
                    }
                } else {
                    guard let id = try String.fetchOne(db, sql: "SELECT id FROM sources WHERE filename = ? AND isSample = 0", arguments: [stem]) else {
                        throw MDictError.missingDictionary
                    }
                    try reader.records { path, data in
                        guard let normalized = ResourcePath.normalize(path) else { throw MDictError.malformed("invalid resource path") }
                        try db.execute(sql: "INSERT OR REPLACE INTO resources(dictionaryID, path, payload) VALUES (?, ?, ?)",
                                       arguments: [id, normalized, data])
                    }
                }
            }
            try Task.checkCancellation()
        }
    }

    public func removeSource(id: String) throws {
        try database.write { db in try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [id]) }
    }

    private static func insert(_ entry: DictionaryEntry, db: Database) throws {
        let data = try JSONEncoder().encode(entry)
        try db.execute(sql: "INSERT INTO entries(id, dictionaryID, headword, payload) VALUES (?, ?, ?, ?)",
                       arguments: [entry.id, entry.dictionaryID, entry.headword, data])
        try db.execute(sql: "INSERT INTO entries_fts(rowid, headword) VALUES (?, ?)", arguments: [db.lastInsertedRowID, entry.headword])
    }

    private static func summary(_ html: String) -> String {
        if html.hasPrefix("@@@LINK=") { return "See " + html.dropFirst(8) }
        let text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(400))
    }
}
