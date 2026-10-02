import Foundation
import FolioArchive

struct MDictEncryption: OptionSet, Sendable {
    let rawValue: UInt8
    static let registered = Self(rawValue: 1)
    static let keyIndex = Self(rawValue: 2)

    init(rawValue: UInt8) { self.rawValue = rawValue }

    init(attribute: String?) throws {
        let value = (attribute ?? "No").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch value {
        case "", "no": self.init(rawValue: 0)
        case "yes": self.init(rawValue: 1)
        default:
            guard let bits = UInt8(value) else { throw MDictError.malformed("Encrypted attribute") }
            guard bits & ~UInt8(3) == 0 else { throw MDictError.unsupported("unknown encryption flags") }
            self.init(rawValue: bits)
        }
    }
}

/// Stateless crypto helpers. Call on the dictionary import actor, before decompression.
enum ArchiveDecryption {
    static func ripemd128(_ data: Data) throws -> Data {
        var digest = Data(count: 16)
        let result = digest.withUnsafeMutableBytes { output in
            data.withUnsafeBytes { input in
                folio_ripemd128(input.bindMemory(to: UInt8.self).baseAddress, input.count,
                                output.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        guard result == 0 else { throw MDictError.malformed("RIPEMD-128 input") }
        return digest
    }

    static func fast(_ data: Data, key: Data) throws -> Data {
        var output = Data(data)
        let result = output.withUnsafeMutableBytes { destination in
            key.withUnsafeBytes { keyBuffer in
                folio_mdict_fast_decrypt(destination.bindMemory(to: UInt8.self).baseAddress, destination.count,
                                         keyBuffer.bindMemory(to: UInt8.self).baseAddress, keyBuffer.count)
            }
        }
        guard result == 0 else { throw MDictError.malformed("fast decryption key") }
        return output
    }

    static func salsa20(_ data: Data, key: Data, nonce: Data = Data(repeating: 0, count: 8),
                        counter: UInt64 = 0) throws -> Data {
        guard nonce.count == 8 else { throw MDictError.malformed("Salsa20 nonce") }
        var output = Data(data)
        let result = output.withUnsafeMutableBytes { destination in
            key.withUnsafeBytes { keyBuffer in
                nonce.withUnsafeBytes { nonceBuffer in
                    folio_salsa20_8_xor(destination.bindMemory(to: UInt8.self).baseAddress, destination.count,
                                        keyBuffer.bindMemory(to: UInt8.self).baseAddress, keyBuffer.count,
                                        nonceBuffer.bindMemory(to: UInt8.self).baseAddress, counter)
                }
            }
        }
        guard result == 0 else { throw MDictError.malformed("Salsa20 key") }
        return output
    }

    /// The v2 key-info scheme encrypts everything AFTER the 8-byte compression/checksum header.
    /// Its salt is little-endian 0x3695; this differs from encryption on individual blocks.
    static func keyIndex(_ block: Data) throws -> Data {
        guard block.count >= 8, Array(block.prefix(4)) == [2, 0, 0, 0] else {
            throw MDictError.malformed("encrypted keyword index header")
        }
        var seed = block.subdata(in: 4 ..< 8)
        seed.append(contentsOf: [0x95, 0x36, 0, 0])
        let key = try ripemd128(seed)
        var result = Data(block.prefix(8))
        result.append(try fast(Data(block.dropFirst(8)), key: key))
        return result
    }

    /// Block descriptor: compression bits 0...3, cipher bits 4...7, prefix length bits 8...15.
    /// Self-contained blocks derive the key from the original four checksum bytes.
    static func blockPayload(_ payload: Data, descriptor: UInt64, checksumBytes: Data) throws -> Data {
        let method = (descriptor >> 4) & 0xf
        guard method != 0 else { return payload }
        guard method == 1 || method == 2 else { throw MDictError.unsupported("block encryption method \(method)") }
        let count = min(Int((descriptor >> 8) & 0xff), payload.count)
        let key = try ripemd128(checksumBytes)
        let prefix = Data(payload.prefix(count))
        var output = try method == 1 ? fast(prefix, key: key) : salsa20(prefix, key: key)
        output.append(payload.dropFirst(count))
        return output
    }
}
