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
        guard (1...8).contains(width) else { throw MDictError.malformed("integer width") }
        let value = try bytes(width)
        let sequence = littleEndian ? Array(value.reversed()) : Array(value)
        return sequence.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    mutating func size(_ width: Int = 8, maximum: Int = 64 * 1_024 * 1_024) throws -> Int {
        guard maximum >= 0 else { throw MDictError.limitExceeded }
        let value = try integer(width)
        guard value <= UInt64(maximum) else { throw MDictError.limitExceeded }
        return Int(value)
    }

    mutating func terminatedText(encoding: String.Encoding, width: Int) throws -> String {
        guard width == 1 || width == 2 else { throw MDictError.malformed("invalid text encoding") }
        let start = offset
        let end: Int? = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var position = start
            while position <= buffer.count - width {
                if buffer[position] == 0 && (width == 1 || buffer[position + 1] == 0) { return position }
                position += width
            }
            return nil
        }
        guard let end else { throw MDictError.malformed("unterminated key") }
        guard end - start <= 16_384 else { throw MDictError.limitExceeded }
        offset = end + width
        guard let text = String(data: data.subdata(in: start..<end), encoding: encoding) else { throw MDictError.malformed("invalid text encoding") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard count >= 0, offset <= length, UInt64(count) <= length - offset else {
            throw MDictError.malformed("truncated file")
        }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw MDictError.malformed("short read")
        }
        offset += UInt64(count)
        return data
    }

    func seek(to position: UInt64) throws {
        guard position <= length else { throw MDictError.malformed("truncated file") }
        try handle.seek(toOffset: position)
        offset = position
    }
}

enum MDictBounds {
    static func add(_ lhs: UInt64, _ rhs: UInt64) throws -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, value <= UInt64(Int64.max) else { throw MDictError.limitExceeded }
        return value
    }
    static func sqlite(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(Int64.max) else { throw MDictError.limitExceeded }
        return Int64(value)
    }
}

func archiveAutoreleasePool<T>(_ operation: () throws -> T) rethrows -> T {
    #if canImport(ObjectiveC)
    return try autoreleasepool(invoking: operation)
    #else
    return try operation()
    #endif
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
        // For the usual unencrypted block, inflate directly from the packed buffer.
        // This avoids an additional dictionary-block-sized payload copy.
        let encrypted = (descriptor >> 4) & 0xf != 0
        let payload: Data? = try encrypted ? ArchiveDecryption.blockPayload(cursor.bytes(cursor.remaining), descriptor: descriptor,
            checksumBytes: block.subdata(in: 4..<8)) : nil
        let output: Data
        switch compression {
        case 0: output = payload ?? block.subdata(in: 8..<block.count)
        case 2:
            var decoded = Data(count: max(1, expectedSize))
            var size = UInt64(max(1, expectedSize))
            let result = decoded.withUnsafeMutableBytes { destination in
                if let payload {
                    return payload.withUnsafeBytes { source in
                        folio_inflate(source.bindMemory(to: UInt8.self).baseAddress, UInt64(source.count),
                                      destination.bindMemory(to: UInt8.self).baseAddress, &size)
                    }
                }
                return block.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                    folio_inflate(source.bindMemory(to: UInt8.self).baseAddress?.advanced(by: 8), UInt64(source.count - 8),
                                  destination.bindMemory(to: UInt8.self).baseAddress, &size)
                }
            }
            guard result == 0, size == UInt64(expectedSize) else { throw MDictError.malformed("invalid zlib block") }
            output = expectedSize == 0 ? Data() : decoded
        case 1: throw MDictError.unsupported("LZO compression")
        default: throw MDictError.unsupported("unknown compression")
        }
        guard output.count == expectedSize, UInt64(self.checksum(output)) == checksum else {
            throw MDictError.malformed("block checksum or size mismatch")
        }
        return output
    }
}
