import Foundation
import GRDB

/// Disk-backed staging index. No dictionary-sized Swift arrays or resource BLOBs.
final class MDictIndexDatabase {
    let database: DatabaseQueue
    let url: URL
    private let temporaryDirectory: URL?

    init(url: URL? = nil) throws {
        if let url { self.url = url; temporaryDirectory = nil }
        else {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.KeyIndex.\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.url = folder.appendingPathComponent("index.sqlite")
            temporaryDirectory = folder
        }
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA cache_size = -2048; PRAGMA temp_store = FILE;")
        }
        database = try DatabaseQueue(path: self.url.path, configuration: configuration)
        try database.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS keys(sequence INTEGER PRIMARY KEY, recordOffset INTEGER NOT NULL, text TEXT NOT NULL);
                CREATE INDEX IF NOT EXISTS keys_offset ON keys(recordOffset);
                CREATE INDEX IF NOT EXISTS keys_text ON keys(text);
                CREATE TABLE IF NOT EXISTS blocks(sequence INTEGER PRIMARY KEY, fileOffset INTEGER NOT NULL,
                    compressed INTEGER NOT NULL, expanded INTEGER NOT NULL, recordOffset INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS blocks_offset ON blocks(recordOffset);
                CREATE TABLE IF NOT EXISTS metadata(name TEXT PRIMARY KEY, value BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS entries(id TEXT PRIMARY KEY, headword TEXT NOT NULL COLLATE NOCASE, payload BLOB NOT NULL);
                CREATE INDEX IF NOT EXISTS entry_headword ON entries(headword);
                CREATE VIRTUAL TABLE IF NOT EXISTS entries_fts USING fts5(headword, tokenize='unicode61 remove_diacritics 2');
                """)
        }
    }

    // Explicit synchronous wrappers avoid selecting GRDB's async overloads inside
    // the actor's bounded batch closures. Task.yield happens after each transaction.
    func write<T>(_ body: (Database) throws -> T) throws -> T { try database.write(body) }
    func read<T>(_ body: (Database) throws -> T) throws -> T { try database.read(body) }

    deinit {
        try? database.close()
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func resource(path: String) throws -> Data? {
        try database.read { db in
            guard let offset = try Int64.fetchOne(db, sql: "SELECT recordOffset FROM keys WHERE text = ? LIMIT 1", arguments: [path]),
                  let identityData = try Data.fetchOne(db, sql: "SELECT value FROM metadata WHERE name = 'archive'"),
                  let total = try Int64.fetchOne(db, sql: "SELECT CAST(value AS INTEGER) FROM metadata WHERE name = 'totalExpanded'") else { return nil }
            let end = try Int64.fetchOne(db, sql: "SELECT recordOffset FROM keys WHERE recordOffset > ? ORDER BY recordOffset LIMIT 1", arguments: [offset]) ?? total
            guard offset >= 0, end >= offset else { throw MDictError.malformed("record range") }
            let identity = try JSONDecoder().decode(MDictArchiveIdentity.self, from: identityData)
            return try ArchiveFileAccess.read([identity.currentURL]) {
                try identity.checkCurrent()
                let file = try ArchiveFile(url: identity.currentURL)
                let value = try MDictRecordReader.read(file: file, database: db, start: UInt64(offset), end: UInt64(end))
                try identity.checkCurrent()
                return value
            }
        }
    }
}

struct MDictArchiveIdentity: Codable, Sendable, Equatable {
    let url: URL
    let inDocuments: Bool
    let stamp: ArchiveFileStamp

    var currentURL: URL {
        guard inDocuments, let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return url }
        return root.appendingPathComponent(stamp.filename)
    }

    static func capture(_ url: URL) throws -> Self {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
        return Self(url: url, inDocuments: url.deletingLastPathComponent().resolvingSymlinksInPath() == documents,
                    stamp: try ArchiveFileStamp.read(url, root: url.deletingLastPathComponent()))
    }

    func checkCurrent() throws {
        do {
            guard try ArchiveFileStamp.read(currentURL, root: currentURL.deletingLastPathComponent()) == stamp else {
                throw DocumentsDictionaryError.changingFile
            }
        } catch let error as DocumentsDictionaryError { throw error }
        catch { throw DocumentsDictionaryError.unreadableFile(stamp.filename) }
    }
}

enum MDictRecordReader {
    struct Cache { var position: UInt64?; var data: Data? }
    static let maximumRecord: UInt64 = 32 * 1_024 * 1_024

    static func read(file: ArchiveFile, database: Database, start: UInt64, end: UInt64) throws -> Data {
        var cache = Cache()
        return try read(file: file, database: database, start: start, end: end, cache: &cache)
    }

    static func read(file: ArchiveFile, database: Database, start: UInt64, end: UInt64, cache: inout Cache) throws -> Data {
        guard start <= end, end - start <= maximumRecord else { throw MDictError.limitExceeded }
        var result = Data()
        let blocks = try Row.fetchCursor(database, sql: """
            SELECT * FROM blocks WHERE recordOffset < ? AND recordOffset + expanded > ? ORDER BY sequence
            """, arguments: [try MDictBounds.sqlite(end), try MDictBounds.sqlite(start)])
        var covered = start
        while let block = try blocks.next() {
            try Task.checkCancellation()
            let position: Int64 = block["fileOffset"], compressed: Int64 = block["compressed"]
            let offset: Int64 = block["recordOffset"], expanded: Int64 = block["expanded"]
            guard position >= 0, offset >= 0, compressed >= 8, compressed <= 64 * 1_024 * 1_024,
                  expanded >= 0, expanded <= 64 * 1_024 * 1_024 else { throw MDictError.limitExceeded }
            let blockEnd = try MDictBounds.add(UInt64(offset), UInt64(expanded))
            guard UInt64(offset) <= covered else { throw MDictError.malformed("record range") }
            let bytes: Data
            if cache.position == UInt64(position), let data = cache.data { bytes = data }
            else {
                cache.position = nil; cache.data = nil
                try file.seek(to: UInt64(position))
                bytes = try ArchiveCompression.unpack(file.read(Int(compressed)), expectedSize: Int(expanded))
                cache.position = UInt64(position); cache.data = bytes
            }
            let lower = max(start, UInt64(offset)) - UInt64(offset)
            let upper = min(end, blockEnd) - UInt64(offset)
            result.append(bytes[Int(lower)..<Int(upper)])
            covered = min(end, blockEnd)
        }
        guard covered == end, UInt64(result.count) == end - start else { throw MDictError.malformed("incomplete records or trailing bytes") }
        return result
    }
}
