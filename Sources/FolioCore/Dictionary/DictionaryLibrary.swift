import Foundation
import GRDB

/// All archive I/O, decompression, and indexing stays on this actor's executor.
/// Only immutable Sendable values cross back into the UI.
public actor DictionaryLibrary: DictionaryRepository {
    let database: DatabaseQueue
    let indexRoot: URL
    var indexCache: [String: MDictIndexDatabase] = [:]
    var importTask: Task<Void, any Error>?
    var importRequest = UUID()

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
        migrator.registerMigration("documents-archives-v2") { db in
            try db.execute(sql: """
                CREATE TABLE managed_archives (
                    stem TEXT PRIMARY KEY,
                    sourceID TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                    snapshot BLOB NOT NULL
                );
                """)
        }
        migrator.registerMigration("massive-indexes-v3") { db in
            try db.execute(sql: """
                ALTER TABLE sources ADD COLUMN definitionIndex TEXT;
                ALTER TABLE sources ADD COLUMN resourceIndex TEXT;
                ALTER TABLE sources ADD COLUMN indexedEntries INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE sources ADD COLUMN indexedResources INTEGER NOT NULL DEFAULT 0;
                """)
        }
        try migrator.migrate(queue)
        database = queue
        if path == ":memory:" {
            indexRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.Indexes.\(UUID().uuidString)", isDirectory: true)
        } else {
            indexRoot = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("Indexes", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: indexRoot, withIntermediateDirectories: true)
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
        try search(query, sourceID: nil)
    }

    public func search(_ query: String, dictionaryID: String) throws -> [DictionaryEntry] {
        try search(query, sourceID: dictionaryID)
    }

    private func search(_ query: String, sourceID: String?) throws -> [DictionaryEntry] {
        let trimmed = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        if let sourceID, let index = try definitionIndex(sourceID) { return try Self.searchIndex(trimmed, index: index) }
        let legacy = try database.read { db in
            if trimmed.isEmpty {
                return try Self.browseEntries(in: db, dictionaryID: sourceID, limit: 30)
            } else {
                let decodedQuery = HTMLEntityDecoder.decode(trimmed)
                // Quote each token so user input cannot become an FTS operator.
                let tokens = decodedQuery.split(whereSeparator: { $0.isWhitespace })
                let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
                let rows = try Row.fetchAll(db, sql: """
                    SELECT e.payload FROM entries e JOIN entries_fts f ON f.rowid = e.rowid
                    WHERE entries_fts MATCH ? AND (? IS NULL OR e.dictionaryID = ?)
                    ORDER BY (e.headword = ? COLLATE NOCASE) DESC, length(e.headword), e.headword LIMIT 50
                    """, arguments: [match, sourceID, sourceID, decodedQuery])
                return try rows.map { try JSONDecoder().decode(DictionaryEntry.self, from: $0["payload"]) }
            }
        }
        guard sourceID == nil else { return legacy }
        var values = legacy
        for id in try indexedSourceIDs() {
            if let index = try definitionIndex(id) { values += try Self.searchIndex(trimmed, index: index) }
        }
        if trimmed.isEmpty {
            var seen = Set<String>()
            return values.filter { seen.insert($0.id).inserted && seen.insert($0.headword.lowercased()).inserted }.shuffled()
        }
        return Array(values.sorted { $0.headword.localizedCaseInsensitiveCompare($1.headword) == .orderedAscending }.prefix(50))
    }

    public func entry(id: String) throws -> DictionaryEntry? {
        if let entry = try Self.entry(id: id, database: database) { return entry }
        for source in try indexedSourceIDs() {
            if let index = try definitionIndex(source), let entry = try Self.entry(id: id, database: index.database) { return entry }
        }
        return nil
    }

    public func lookup(_ headword: String, dictionaryID: String) throws -> DictionaryEntry? {
        let indexed = try definitionIndex(dictionaryID)
        let queue = indexed?.database ?? database
        return try queue.read { db in
            var target = HTMLEntityDecoder.decode(headword)
            var visited: Set<String> = []
            for _ in 0..<12 {
                let escaped = HTMLEntityDecoder.escape(target)
                let sql = indexed == nil
                    ? "SELECT payload FROM entries WHERE (headword = ? OR headword = ?) AND dictionaryID = ? LIMIT 1"
                    : "SELECT payload FROM entries WHERE (headword = ? OR headword = ?) LIMIT 1"
                let arguments: StatementArguments = indexed == nil ? [target, escaped, dictionaryID] : [target, escaped]
                guard visited.insert(target.lowercased()).inserted,
                      let data = try Data.fetchOne(db, sql: sql, arguments: arguments) else { return nil }
                let entry = try JSONDecoder().decode(DictionaryEntry.self, from: data)
                if entry.html.hasPrefix("@@@LINK=") {
                    target = HTMLEntityDecoder.decode(String(entry.html.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    return entry
                }
            }
            throw MDictError.malformed("dictionary link cycle")
        }
    }

    /// Curated random sampling of valid headwords for dictionary browsing.
    /// Excludes symbols, numbers, affixes/suffixes, and redirect definitions.
    static func browseEntries(in db: Database, dictionaryID: String? = nil, limit: Int = 30) throws -> [DictionaryEntry] {
        let hasDict = dictionaryID != nil
        let whereClause = hasDict
            ? "WHERE dictionaryID = ? AND headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
            : "WHERE headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
        let whereArgs: StatementArguments = hasDict ? [dictionaryID] : []

        guard let stats = try Row.fetchOne(db, sql: "SELECT count(*), min(rowid), max(rowid) FROM entries \(whereClause)", arguments: whereArgs),
              let count = stats[0] as Int?, count > 0,
              let minRow = stats[1] as Int64?,
              let maxRow = stats[2] as Int64? else {
            return []
        }

        var results: [DictionaryEntry] = []
        var seenIDs = Set<String>()
        var seenHeadwords = Set<String>()

        func appendIfValid(_ data: Data) {
            guard let entry = try? JSONDecoder().decode(DictionaryEntry.self, from: data) else { return }
            guard entry.isValidForBrowse else { return }
            guard seenIDs.insert(entry.id).inserted else { return }
            guard seenHeadwords.insert(entry.headword.lowercased()).inserted else { return }
            results.append(entry)
        }

        // 1. Prioritize curated common English headwords
        let curatedSample = CuratedHeadwords.common.shuffled().prefix(40)
        let placeholders = Array(repeating: "?", count: curatedSample.count).joined(separator: ",")
        let curatedWhere = hasDict
            ? "WHERE dictionaryID = ? AND headword IN (\(placeholders)) AND headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
            : "WHERE headword IN (\(placeholders)) AND headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
        var curatedArgs: [any DatabaseValueConvertible] = []
        if let dictionaryID { curatedArgs.append(dictionaryID) }
        for word in curatedSample { curatedArgs.append(word) }

        for row in try Row.fetchAll(db, sql: "SELECT payload FROM entries \(curatedWhere) LIMIT \(limit)", arguments: StatementArguments(curatedArgs)) {
            appendIfValid(row["payload"])
            if results.count >= limit { break }
        }

        // 2. Sample random entries across the dictionary index
        if results.count < limit {
            if count <= limit * 2 {
                let allRows = try Row.fetchAll(db, sql: "SELECT payload FROM entries \(whereClause) LIMIT 100", arguments: whereArgs)
                for row in allRows.shuffled() {
                    appendIfValid(row["payload"])
                    if results.count >= limit { break }
                }
            } else {
                var attempts = 0
                while results.count < limit && attempts < 3 {
                    attempts += 1
                    let needed = limit - results.count
                    let sampleCount = min(Int(count), max(needed * 4, 30))
                    var targetRowIDs = Set<Int64>()
                    while targetRowIDs.count < sampleCount {
                        let id = Int64.random(in: minRow...maxRow)
                        targetRowIDs.insert(id)
                    }
                    let idPlaceholders = Array(repeating: "?", count: targetRowIDs.count).joined(separator: ",")
                    let sampleWhere = hasDict
                        ? "WHERE dictionaryID = ? AND rowid IN (\(idPlaceholders)) AND headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
                        : "WHERE rowid IN (\(idPlaceholders)) AND headword GLOB '[a-zA-Z]*' AND headword NOT GLOB '*-' AND headword NOT GLOB '[Ss][Ee][Ee] *'"
                    var sampleArgs: [any DatabaseValueConvertible] = []
                    if let dictionaryID { sampleArgs.append(dictionaryID) }
                    for id in targetRowIDs { sampleArgs.append(id) }

                    for row in try Row.fetchAll(db, sql: "SELECT payload FROM entries \(sampleWhere) LIMIT \(limit)", arguments: StatementArguments(sampleArgs)) {
                        appendIfValid(row["payload"])
                        if results.count >= limit { break }
                    }
                }
            }
        }

        return Array(results.prefix(limit))
    }

    public func sources() throws -> [DictionarySource] {
        try database.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.*, CASE WHEN s.definitionIndex IS NULL THEN (SELECT count(*) FROM entries WHERE dictionaryID = s.id) ELSE s.indexedEntries END AS entryCount,
                    CASE WHEN s.resourceIndex IS NULL THEN (SELECT count(*) FROM resources WHERE dictionaryID = s.id) ELSE s.indexedResources END AS resourceCount
                FROM sources s ORDER BY isSample, title
                """).map {
                    DictionarySource(id: $0["id"], title: $0["title"], filename: $0["filename"],
                                     entryCount: $0["entryCount"], resourceCount: $0["resourceCount"], isSample: $0["isSample"])
                }
        }
    }

    public func resource(path: String, dictionaryID: String) throws -> Data? {
        guard let key = ResourcePath.normalize(path) else { return nil }
        if let index = try resourceIndex(dictionaryID) {
            do { return try archiveAutoreleasePool { try index.resource(path: key) } }
            catch {
                if !(error is CancellationError) { ArchiveDiagnostics.report(filename: key, error: error) }
                if !(error is CancellationError), !(error is any FolioMessageProviding) { throw DocumentsDictionaryError.unreadableFile(key) }
                throw error
            }
        }
        return try database.read { db in
            try Data.fetchOne(db, sql: "SELECT payload FROM resources WHERE dictionaryID = ? AND path = ?", arguments: [dictionaryID, key])
        }
    }

    public func removeSource(id: String) throws {
        let files = try indexFiles(sourceID: id)
        try database.write { db in try db.execute(sql: "DELETE FROM sources WHERE id = ?", arguments: [id]) }
        removeIndexFiles(files)
    }

    private static func insert(_ entry: DictionaryEntry, db: Database) throws {
        let data = try JSONEncoder().encode(entry)
        try db.execute(sql: "INSERT INTO entries(id, dictionaryID, headword, payload) VALUES (?, ?, ?, ?)",
                       arguments: [entry.id, entry.dictionaryID, entry.headword, data])
        try db.execute(sql: "INSERT INTO entries_fts(rowid, headword) VALUES (?, ?)", arguments: [db.lastInsertedRowID, entry.headword])
    }

    static func summary(_ html: String) -> String {
        if html.hasPrefix("@@@LINK=") {
            let target = HTMLEntityDecoder.decode(String(html.dropFirst(8))).trimmingCharacters(in: .whitespacesAndNewlines)
            return "See " + target
        }
        let text = html.replacingOccurrences(of: "(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = HTMLEntityDecoder.decode(text)
        return String(decoded.prefix(400))
    }
}
