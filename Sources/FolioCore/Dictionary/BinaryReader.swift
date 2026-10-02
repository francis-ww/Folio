import Foundation
import FolioArchive

struct BinaryCursor {
    let data: Data
    private(set) var offset = 0
    var remaining: Int { data.count - offset }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, count <= remaining else { throw MDictError.malformed("truncated section") }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }

    mutating func integer(_ width: Int, littleEndian: Bool = false) throws -> UInt64 {
        let value = try bytes(width)
        let sequence = littleEndian ? Array(value.reversed()) : Array(value)
        return sequence.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func size(_ width: Int = 8, maximum: Int = 64 * 1_024 * 1_024) throws -> Int {
        let value = try integer(width)
        guard value <= UInt64(maximum) else { throw MDictError.limitExceeded }
        return Int(value)
    }

    mutating func terminatedText(encoding: String.Encoding, width: Int) throws -> String {
        let start = offset
        while remaining >= width {
            let unit = try bytes(width)
            if unit.allSatisfy({ $0 == 0 }) {
                let raw = data.subdata(in: start ..< offset - width)
                guard let text = String(data: raw, encoding: encoding) else {
                    throw MDictError.malformed("invalid text encoding")
                }
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        throw MDictError.malformed("unterminated key")
    }
}

final class ArchiveFile {
    private let handle: FileHandle
    let length: UInt64
    private(set) var offset: UInt64 = 0

    init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        length = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
    }

    deinit { try? handle.close() }

    func read(_ count: Int) throws -> Data {
        guard count >= 0, UInt64(count) <= length - offset else {
            throw MDictError.malformed("truncated file")
        }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw MDictError.malformed("short read")
        }
        offset += UInt64(count)
        return data
    }
}

enum ArchiveCompression {
    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            folio_adler32(buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count)
        }
    }

    static func unpack(_ block: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw MDictError.malformed("negative block size") }
        guard expectedSize <= 64 * 1_024 * 1_024, block.count <= 64 * 1_024 * 1_024 else { throw MDictError.limitExceeded }
        var cursor = BinaryCursor(data: block)
        let descriptor = try cursor.integer(4, littleEndian: true)
        let compression = descriptor & 0xf
        let checksum = try cursor.integer(4)
        let payload = try ArchiveDecryption.blockPayload(cursor.bytes(cursor.remaining), descriptor: descriptor,
                                                         checksumBytes: block.subdata(in: 4 ..< 8))
        let output: Data
        switch compression {
        case 0: output = payload
        case 2:
            var decoded = Data(count: max(1, expectedSize))
            var size = max(1, expectedSize)
            let result = decoded.withUnsafeMutableBytes { destination in
                payload.withUnsafeBytes { source in
                    folio_inflate(source.bindMemory(to: UInt8.self).baseAddress, source.count,
                                  destination.bindMemory(to: UInt8.self).baseAddress, &size)
                }
            }
            guard result == 0, size == expectedSize else { throw MDictError.malformed("invalid zlib block") }
            output = Data(decoded.prefix(size))
        case 1: throw MDictError.unsupported("LZO compression")
        default: throw MDictError.unsupported("unknown compression")
        }
        guard output.count == expectedSize, UInt64(self.checksum(output)) == checksum else {
            throw MDictError.malformed("block checksum or size mismatch")
        }
        return output
    }
}
