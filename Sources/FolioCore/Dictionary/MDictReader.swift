import Foundation
import GRDB

/// Stateful, disk-backed MDict v2 reader. Use only on the background import actor.
/// All absolute/compressed/expanded offsets are UInt64; Int is only a bounded buffer index.
final class MDictReader {
    struct Header {
        let title: String
        let encoding: String.Encoding
        let encryption: MDictEncryption
    }
    private struct KeyBlock { let compressed: UInt64; let expanded: UInt64; let count: Int }
    private let file: ArchiveFile
    let header: Header
    let index: MDictIndexDatabase
    private let resourceArchive: Bool
    private let width: Int
    private var keyBlocks: [KeyBlock] = []
    private var keyBlockPosition = 0
    private var keyCursor: BinaryCursor?
    private var currentBlockCount = 0
    private var currentBlockRead = 0
    private var metadataStarted = false
    private var recordInfo: BinaryCursor?
    private var recordBlockCount = 0
    private var recordBlockPosition = 0
    private var physicalPosition: UInt64 = 0
    private var expandedPosition: UInt64 = 0
    private var keysRead = 0
    private var lastKeyOffset: UInt64 = 0
    private var consumedKeys = 0
    private var blockCache = MDictRecordReader.Cache()
    private var keySectionEnd: UInt64 = 0
    private var recordSectionSize: UInt64 = 0
    private(set) var entryCount = 0
    private(set) var isIndexed = false
    private(set) var totalExpanded: UInt64 = 0
    static let batchSize = 1_000
    private let maximumEntries = 10_000_000

    init(url: URL, resourceArchive: Bool, index: MDictIndexDatabase? = nil) throws {
        file = try ArchiveFile(url: url)
        self.resourceArchive = resourceArchive
        self.index = try index ?? MDictIndexDatabase()
        var length = BinaryCursor(data: try file.read(4))
        let raw = try file.read(length.size(4, maximum: 1_024 * 1_024))
        var check = BinaryCursor(data: try file.read(4))
        guard try check.integer(4, littleEndian: true) == UInt64(ArchiveCompression.checksum(raw)),
              let xml = String(data: raw, encoding: .utf16LittleEndian) else { throw MDictError.malformed("header checksum or encoding") }
        let attrs = Self.attributes(xml)
        guard let version = Double(attrs["GeneratedByEngineVersion"] ?? ""), version >= 2, version < 3 else {
            throw MDictError.unsupported("an engine version other than MDict 2")
        }
        let encryption = try MDictEncryption(attribute: attrs["Encrypted"])
        guard (attrs["StyleSheet"] ?? "").isEmpty else { throw MDictError.unsupported("embedded stylesheet substitutions") }
        let encodingName = resourceArchive ? "UTF-16" : (attrs["Encoding"] ?? "UTF-8").uppercased()
        let encoding: String.Encoding
        switch encodingName {
        case "UTF-8", "UTF8": encoding = .utf8; width = 1
        case "UTF-16", "UTF-16LE": encoding = .utf16LittleEndian; width = 2
        default: throw MDictError.unsupported("\(encodingName) text encoding")
        }
        header = Header(title: attrs["Title"] ?? url.deletingPathExtension().lastPathComponent, encoding: encoding, encryption: encryption)
    }

    /// One transaction, at most 1,000 keywords or block descriptors. The async caller
    /// releases its autorelease pool and yields after every call. Resource payloads are skipped.
    func indexNextBatch() throws -> Bool {
        try Task.checkCancellation()
        guard !isIndexed else { return false }
        if !metadataStarted { try startKeywords(); metadataStarted = true }
        if keysRead < entryCount {
            try index.database.write { db in
                for _ in 0..<Self.batchSize {
                    try Task.checkCancellation()
                    guard keysRead < entryCount else { break }
                    if keyCursor == nil || keyCursor?.remaining == 0 {
                        if keyCursor != nil, currentBlockRead != currentBlockCount { throw MDictError.malformed("key block counts") }
                        guard keyBlockPosition < keyBlocks.count else { throw MDictError.malformed("entry count") }
                        let block = keyBlocks[keyBlockPosition]
                        keyBlockPosition += 1
                        keyCursor = nil // Release the previous block before allocating the next.
                        keyCursor = BinaryCursor(data: try ArchiveCompression.unpack(file.read(Int(block.compressed)), expectedSize: Int(block.expanded)))
                        currentBlockCount = block.count; currentBlockRead = 0
                    }
                    guard var cursor = keyCursor else { throw MDictError.malformed("entry count") }
                    let offset = try cursor.integer(8)
                    guard offset >= lastKeyOffset, offset <= UInt64(Int64.max) else { throw MDictError.malformed("unordered record offsets") }
                    let text = try cursor.terminatedText(encoding: header.encoding, width: width)
                    guard text.utf8.count <= 16_384 else { throw MDictError.limitExceeded }
                    let key = resourceArchive ? ResourcePath.normalize(text) : text
                    guard let key else { throw MDictError.malformed("invalid resource path") }
                    try db.execute(sql: "INSERT INTO keys(sequence, recordOffset, text) VALUES (?, ?, ?)",
                        arguments: [keysRead + 1, try MDictBounds.sqlite(offset), key])
                    keysRead += 1; currentBlockRead += 1; lastKeyOffset = offset; keyCursor = cursor
                }
            }
            return true
        }
        if recordInfo == nil { try startRecords() }
        guard var info = recordInfo else { throw MDictError.malformed("record metadata size") }
        try index.database.write { db in
            for _ in 0..<Self.batchSize where recordBlockPosition < recordBlockCount {
                try Task.checkCancellation()
                let compressed = try info.size(), expanded = try info.size()
                guard compressed >= 8 else { throw MDictError.malformed("truncated section") }
                try db.execute(sql: "INSERT INTO blocks(sequence, fileOffset, compressed, expanded, recordOffset) VALUES (?, ?, ?, ?, ?)",
                    arguments: [recordBlockPosition, try MDictBounds.sqlite(physicalPosition), compressed, expanded, try MDictBounds.sqlite(expandedPosition)])
                physicalPosition = try MDictBounds.add(physicalPosition, UInt64(compressed))
                expandedPosition = try MDictBounds.add(expandedPosition, UInt64(expanded))
                recordBlockPosition += 1
            }
        }
        recordInfo = info
        if recordBlockPosition == recordBlockCount {
            guard info.remaining == 0, physicalPosition == file.length,
                  lastKeyOffset <= expandedPosition else { throw MDictError.malformed("record block boundaries") }
            totalExpanded = expandedPosition
            try index.database.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO metadata(name, value) VALUES ('totalExpanded', ?)", arguments: [String(totalExpanded)])
            }
            keyBlocks = []; keyCursor = nil; recordInfo = nil
            isIndexed = true
            return false
        }
        return true
    }

    /// Only a bounded page of keyword metadata is held, and records are consumed
    /// individually inside the destination's 1,000-word transaction (4 MiB byte budget).
    func readRecordBatch(_ consume: (String, Data) throws -> Void) throws -> Bool {
        guard isIndexed else { throw MDictError.malformed("record metadata size") }
        let rows = try index.database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM keys WHERE sequence > ? ORDER BY sequence LIMIT 1001", arguments: [consumedKeys])
        }
        var bytesRead = 0
        var lastOffset: UInt64?
        var lastContent: Data?
        for position in 0..<min(Self.batchSize, rows.count) {
            try Task.checkCancellation()
            let start = UInt64(rows[position]["recordOffset"] as Int64)
            let next = position + 1 < rows.count ? UInt64(rows[position + 1]["recordOffset"] as Int64) : totalExpanded
            let end: UInt64
            if next > start { end = next }
            else {
                end = try index.database.read { db in
                    try Int64.fetchOne(db, sql: "SELECT recordOffset FROM keys WHERE recordOffset > ? ORDER BY recordOffset LIMIT 1",
                        arguments: [try MDictBounds.sqlite(start)]).map(UInt64.init) ?? totalExpanded
                }
            }
            guard end >= start, end - start <= (resourceArchive ? MDictRecordReader.maximumRecord : 4 * 1_024 * 1_024) else {
                throw MDictError.limitExceeded
            }
            let content: Data
            if lastOffset == start, let lastContent { content = lastContent }
            else { content = try index.database.read { db in try MDictRecordReader.read(file: file, database: db, start: start, end: end, cache: &blockCache) } }
            try consume(rows[position]["text"], content)
            consumedKeys += 1; bytesRead += content.count
            lastOffset = start; lastContent = content
            if bytesRead >= 4 * 1_024 * 1_024 { break }
        }
        if consumedKeys == entryCount { blockCache = .init() }
        return consumedKeys < entryCount
    }

    /// Synchronous fixture/diagnostic convenience. Production uses the two batched APIs.
    func records(_ consume: (String, Data) throws -> Void) throws {
        while try archiveAutoreleasePool({ try indexNextBatch() }) {}
        while try archiveAutoreleasePool({ try readRecordBatch(consume) }) {}
    }

    private func startKeywords() throws {
        var metadata = BinaryCursor(data: try file.read(40)), checksum = BinaryCursor(data: try file.read(4))
        guard try checksum.integer(4) == UInt64(ArchiveCompression.checksum(metadata.data)) else {
            if header.encryption.contains(.registered) { throw MDictError.passcodeRequired }
            throw MDictError.malformed("key metadata checksum")
        }
        let blockCount = try metadata.size(maximum: 1_000_000)
        entryCount = try metadata.size(maximum: maximumEntries)
        let expanded = try metadata.size(), compressed = try metadata.size()
        let sectionSize = try metadata.integer(8)
        let packed = try file.read(compressed)
        let decoded = try header.encryption.contains(.keyIndex) ? ArchiveDecryption.keyIndex(packed) : packed
        var info = BinaryCursor(data: try ArchiveCompression.unpack(decoded, expectedSize: expanded))
        var entries = 0, section: UInt64 = 0
        for _ in 0..<blockCount {
            let count = try info.size(maximum: maximumEntries)
            guard entries <= maximumEntries - count else { throw MDictError.limitExceeded }
            entries += count
            for _ in 0..<2 {
                let characters = try info.size(2, maximum: 65_535)
                _ = try info.bytes((characters + 1) * width)
            }
            let compressed = UInt64(try info.size()), expanded = UInt64(try info.size())
            section = try MDictBounds.add(section, compressed)
            keyBlocks.append(KeyBlock(compressed: compressed, expanded: expanded, count: count))
        }
        guard info.remaining == 0, entries == entryCount, section == sectionSize else { throw MDictError.malformed("key block counts") }
        keySectionEnd = try MDictBounds.add(file.offset, sectionSize)
        guard keySectionEnd <= file.length else { throw MDictError.malformed("truncated file") }
    }

    private func startRecords() throws {
        guard (keyCursor?.remaining ?? 0) == 0, currentBlockRead == currentBlockCount,
              keyBlockPosition == keyBlocks.count, file.offset == keySectionEnd else { throw MDictError.malformed("entry count") }
        let first = try index.database.read { db in try Int64.fetchOne(db, sql: "SELECT recordOffset FROM keys ORDER BY sequence LIMIT 1") }
        guard first == 0 || entryCount == 0 else { throw MDictError.malformed("record block boundaries") }
        var metadata = BinaryCursor(data: try file.read(32))
        recordBlockCount = try metadata.size(maximum: 1_000_000)
        guard try metadata.size(maximum: maximumEntries) == entryCount else { throw MDictError.malformed("record entry count") }
        let infoSize = try metadata.size()
        recordSectionSize = try metadata.integer(8)
        guard infoSize == recordBlockCount * 16 else { throw MDictError.malformed("record metadata size") }
        recordInfo = BinaryCursor(data: try file.read(infoSize))
        physicalPosition = file.offset
        guard try MDictBounds.add(physicalPosition, recordSectionSize) == file.length else { throw MDictError.malformed("incomplete records or trailing bytes") }
    }

    private static func attributes(_ xml: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(pattern: "(\\w+)=([\"'])(.*?)\\2", options: .dotMatchesLineSeparators) else { return [:] }
        let source = xml as NSString
        return expression.matches(in: xml, range: NSRange(location: 0, length: source.length)).reduce(into: [:]) { values, match in
            values[source.substring(with: match.range(at: 1))] = source.substring(with: match.range(at: 3))
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
        }
    }
}
