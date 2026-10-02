import Foundation

/// A bounded, streaming reader for unencrypted MDict v2 UTF-8/UTF-16 archives.
/// Call only from a background actor. Resource and definition records may span blocks.
struct MDictReader {
    struct Header {
        let title: String
        let encoding: String.Encoding
    }
    private struct Key {
        let offset: Int
        let text: String
    }
    private struct Block {
        let compressed: Int
        let expanded: Int
    }

    private let file: ArchiveFile
    let header: Header
    private let width: Int
    private let maximumEntries = 1_000_000
    private let maximumRecord = 32 * 1_024 * 1_024

    init(url: URL, resourceArchive: Bool) throws {
        file = try ArchiveFile(url: url)
        var length = BinaryCursor(data: try file.read(4))
        let raw = try file.read(length.size(4, maximum: 1_024 * 1_024))
        var check = BinaryCursor(data: try file.read(4))
        guard try check.integer(4, littleEndian: true) == UInt64(ArchiveCompression.checksum(raw)),
              let xml = String(data: raw, encoding: .utf16LittleEndian) else {
            throw MDictError.malformed("header checksum or encoding")
        }
        let attrs = Self.attributes(xml)
        guard let version = Double(attrs["GeneratedByEngineVersion"] ?? ""), version >= 2, version < 3 else {
            throw MDictError.unsupported("an engine version other than MDict 2")
        }
        let encrypted = (attrs["Encrypted"] ?? "No").lowercased()
        guard ["no", "0", ""].contains(encrypted) else { throw MDictError.unsupported("encryption") }
        guard (attrs["StyleSheet"] ?? "").isEmpty else { throw MDictError.unsupported("embedded stylesheet substitutions") }
        let encodingName = resourceArchive ? "UTF-16" : (attrs["Encoding"] ?? "UTF-8").uppercased()
        let encoding: String.Encoding
        switch encodingName {
        case "UTF-8", "UTF8": encoding = .utf8; width = 1
        case "UTF-16", "UTF-16LE": encoding = .utf16LittleEndian; width = 2
        default: throw MDictError.unsupported("\(encodingName) text encoding")
        }
        header = Header(title: attrs["Title"] ?? url.deletingPathExtension().lastPathComponent, encoding: encoding)
    }

    func records(_ consume: (String, Data) throws -> Void) throws {
        var metadata = BinaryCursor(data: try file.read(40))
        let keyBlockCount = try metadata.size(maximum: 100_000)
        let entryCount = try metadata.size(maximum: maximumEntries)
        let infoExpanded = try metadata.size()
        let infoSize = try metadata.size()
        let keySectionSize = try metadata.size(maximum: Int.max)
        var checksum = BinaryCursor(data: try file.read(4))
        guard try checksum.integer(4) == UInt64(ArchiveCompression.checksum(metadata.data)) else {
            throw MDictError.malformed("key metadata checksum")
        }
        var info = BinaryCursor(data: try ArchiveCompression.unpack(file.read(infoSize), expectedSize: infoExpanded))
        var keyBlocks: [Block] = []
        var describedEntries = 0
        for _ in 0 ..< keyBlockCount {
            describedEntries += try info.size(maximum: maximumEntries)
            for _ in 0 ..< 2 {
                let characters = try info.size(2, maximum: 65_535)
                _ = try info.bytes((characters + 1) * width)
            }
            keyBlocks.append(Block(compressed: try info.size(), expanded: try info.size()))
        }
        guard info.remaining == 0, describedEntries == entryCount,
              keyBlocks.reduce(0, { $0 + $1.compressed }) == keySectionSize else {
            throw MDictError.malformed("key block counts")
        }
        var keys: [Key] = []
        keys.reserveCapacity(entryCount)
        for block in keyBlocks {
            try Task.checkCancellation()
            var cursor = BinaryCursor(data: try ArchiveCompression.unpack(file.read(block.compressed), expectedSize: block.expanded))
            while cursor.remaining > 0 {
                guard keys.count < entryCount else { throw MDictError.malformed("excess keys") }
                let offset = try cursor.size(maximum: Int.max)
                let text = try cursor.terminatedText(encoding: header.encoding, width: width)
                guard offset >= (keys.last?.offset ?? 0) else { throw MDictError.malformed("unordered record offsets") }
                keys.append(Key(offset: offset, text: text))
            }
        }
        guard keys.count == entryCount else { throw MDictError.malformed("entry count") }
        var recordMeta = BinaryCursor(data: try file.read(32))
        let blockCount = try recordMeta.size(maximum: 100_000)
        guard try recordMeta.size(maximum: maximumEntries) == entryCount else {
            throw MDictError.malformed("record entry count")
        }
        let blockInfoSize = try recordMeta.size()
        let recordSectionSize = try recordMeta.size(maximum: Int.max)
        guard blockInfoSize == blockCount * 16 else { throw MDictError.malformed("record metadata size") }
        var recordInfo = BinaryCursor(data: try file.read(blockInfoSize))
        var blocks: [Block] = []
        for _ in 0 ..< blockCount {
            blocks.append(Block(compressed: try recordInfo.size(), expanded: try recordInfo.size()))
        }
        let totalExpanded = blocks.reduce(0) { $0 + $1.expanded }
        guard blocks.reduce(0, { $0 + $1.compressed }) == recordSectionSize,
              totalExpanded <= 8 * 1_024 * 1_024 * 1_024,
              keys.first?.offset == 0 || keys.isEmpty,
              (keys.last?.offset ?? 0) <= totalExpanded else {
            throw MDictError.malformed("record block boundaries")
        }

        var pending = Data()
        var base = 0
        var index = 0
        for block in blocks {
            try Task.checkCancellation()
            pending.append(try ArchiveCompression.unpack(file.read(block.compressed), expectedSize: block.expanded))
            var consumed = 0
            while index < keys.count {
                var endIndex = index + 1
                while endIndex < keys.count, keys[endIndex].offset == keys[index].offset { endIndex += 1 }
                let start = keys[index].offset
                let end = endIndex < keys.count ? keys[endIndex].offset : totalExpanded
                guard end - start <= maximumRecord else { throw MDictError.limitExceeded }
                guard end <= base + pending.count else { break }
                guard start >= base else { throw MDictError.malformed("record range") }
                let content = pending.subdata(in: start - base ..< end - base)
                for key in keys[index ..< endIndex] {
                    try Task.checkCancellation()
                    try consume(key.text, content)
                }
                index = endIndex
                consumed = end - base
            }
            if consumed > 0 { pending = Data(pending.dropFirst(consumed)); base += consumed }
            guard pending.count <= maximumRecord else { throw MDictError.limitExceeded }
        }
        guard index == keys.count, pending.isEmpty, file.offset == file.length else {
            throw MDictError.malformed("incomplete records or trailing bytes")
        }
    }

    private static func attributes(_ xml: String) -> [String: String] {
        guard let expression = try? NSRegularExpression(pattern: "(\\w+)=([\"'])(.*?)\\2", options: .dotMatchesLineSeparators) else { return [:] }
        let source = xml as NSString
        return expression.matches(in: xml, range: NSRange(location: 0, length: source.length)).reduce(into: [:]) { values, match in
            values[source.substring(with: match.range(at: 1))] = source.substring(with: match.range(at: 3))
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
    }
}
