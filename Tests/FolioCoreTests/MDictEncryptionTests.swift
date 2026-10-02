import Foundation
import Testing
import FolioArchive
@testable import FolioCore

struct MDictEncryptionTests {
    private struct Vectors: Decodable {
        struct Hash: Decodable { let input: String; let repeatA: Int; let digest: String }
        struct Salsa: Decodable { let key: String; let nonce: String; let counter: UInt64; let input: String; let output: String }
        struct Fast: Decodable { let key: String; let plain: String; let cipher: String }
        let ripemd: [Hash]
        let salsa: [Salsa]
        let fast: [Fast]
    }

    private func fixture(_ name: String, _ ext: String = "mdx") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    private func vectors() throws -> Vectors {
        try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: fixture("crypto-reference", "json")))
    }

    private func hex(_ value: String) throws -> Data {
        let bytes = Array(value.utf8)
        guard bytes.count % 2 == 0 else { throw MDictError.malformed("test hex length") }
        return try Data(stride(from: 0, to: bytes.count, by: 2).map { index in
            try #require(UInt8(String(decoding: bytes[index ..< index + 2], as: UTF8.self), radix: 16))
        })
    }

    @Test func ripemdMatchesStandardAndIndependentVectors() throws {
        let reference = try vectors()
        #expect(reference.ripemd.count == 15)
        for vector in reference.ripemd {
            let input = try vector.repeatA == 0 ? hex(vector.input) : Data(repeating: 97, count: vector.repeatA)
            #expect(try ArchiveDecryption.ripemd128(input) == hex(vector.digest))
        }
        // Published RIPEMD-128 vector, independent of the fixture generator.
        #expect(try ArchiveDecryption.ripemd128(Data("abc".utf8)) == hex("c14a12199c66e4ba84636b0f69144c77"))
    }

    @Test func salsaEightRoundsMatchIndependentVectors() throws {
        let reference = try vectors()
        #expect(reference.salsa.count == 54)
        for vector in reference.salsa {
            let result = try ArchiveDecryption.salsa20(hex(vector.input), key: hex(vector.key),
                                                       nonce: hex(vector.nonce), counter: vector.counter)
            #expect(try result == hex(vector.output))
        }
    }

    @Test func fastDecryptMatchesIndependentCiphertext() throws {
        let reference = try vectors()
        #expect(reference.fast.count == 7)
        for vector in reference.fast {
            #expect(try ArchiveDecryption.fast(hex(vector.cipher), key: hex(vector.key)) == hex(vector.plain))
        }
    }

    @Test func parsesBitmaskAndLegacyBooleanAttributes() throws {
        #expect(try MDictEncryption(attribute: nil).isEmpty)
        #expect(try MDictEncryption(attribute: "No").isEmpty)
        #expect(try MDictEncryption(attribute: "0").isEmpty)
        #expect(try MDictEncryption(attribute: " Yes ") == .registered)
        #expect(try MDictEncryption(attribute: "1") == .registered)
        #expect(try MDictEncryption(attribute: "2") == .keyIndex)
        #expect(try MDictEncryption(attribute: "3") == [.registered, .keyIndex])
        for invalid in ["-1", "256", "sometimes"] {
            #expect(throws: MDictError.malformed("Encrypted attribute")) { try MDictEncryption(attribute: invalid) }
        }
        #expect(throws: MDictError.unsupported("unknown encryption flags")) { try MDictEncryption(attribute: "4") }
    }

    @Test(arguments: ["encrypted", "fast-encrypted", "salsa-encrypted", "fast-uncompressed", "salsa-uncompressed"])
    func indexesAndLooksUpEncryptedDefinitions(_ name: String) async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.importArchives([fixture(name)])
        let source = try #require(try await library.sources().first)
        #expect(source.entryCount == 4)
        let results = try await library.search("aur")
        let entry = try #require(results.first)
        #expect(entry.headword == "aurora")
        #expect(entry.html == "<p>A ribbon of light — bright across the night sky.</p>")
        #expect(try await library.entry(id: entry.id)?.html == entry.html)
        #expect(try await library.lookup("alias", dictionaryID: source.id)?.html == entry.html)
        #expect(try await library.lookup("redirect", dictionaryID: source.id)?.headword == "aurora")
    }

    @Test func encryptedMDDPreservesCompleteMediaBytes() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.importArchives([fixture("encrypted", "mdd"), fixture("encrypted")])
        let source = try #require(try await library.sources().first)
        #expect(source.resourceCount == 2)
        var originals: [String: Data] = [:]
        let reader = try MDictReader(url: fixture("tiny", "mdd"), resourceArchive: true)
        try reader.records { name, bytes in originals[name] = bytes }
        for (path, bytes) in originals {
            #expect(try await library.resource(path: path, dictionaryID: source.id) == bytes)
        }
    }

    @Test(arguments: ["registered", "registered-both", "registered-yes"])
    func registrationMetadataRequiresPasscode(_ name: String) throws {
        #expect(throws: MDictError.passcodeRequired) {
            let reader = try MDictReader(url: fixture(name), resourceArchive: false)
            try reader.records { _, _ in }
        }
        #expect(MDictError.passcodeRequired.errorDescription?.contains("registration code") == true)
    }

    @Test func registrationBoundMDDRequiresPasscode() throws {
        #expect(throws: MDictError.passcodeRequired) {
            let reader = try MDictReader(url: fixture("registered", "mdd"), resourceArchive: true)
            try reader.records { _, _ in }
        }
    }

    @Test func passcodeFailureRollsBackEntireImportBatch() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.seedSamples()
        let previous = try await library.sources()
        do {
            try await library.importArchives([fixture("encrypted"), fixture("registered-both")])
            Issue.record("Expected a passcode error")
        } catch {
            #expect(error as? MDictError == .passcodeRequired)
        }
        #expect(try await library.sources() == previous)
        #expect(try await library.search("aurora").isEmpty)
    }

    @Test func encryptedIndexStillChecksItsChecksum() throws {
        var bytes = try Data(contentsOf: fixture("encrypted"))
        var length = BinaryCursor(data: bytes.prefix(4))
        let headerSize = try length.size(4, maximum: 1_024 * 1_024)
        let indexStart = 4 + headerSize + 4 + 40 + 4
        bytes[indexStart + 4] ^= 1 // Changes both the expected checksum and the derived key.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mdx")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        #expect(throws: (any Error).self) {
            let reader = try MDictReader(url: url, resourceArchive: false)
            try reader.records { _, _ in }
        }
    }

    @Test func malformedEncryptedBlocksAndKeysAreRejected() throws {
        for size in 0 ..< 8 {
            #expect(throws: (any Error).self) { try ArchiveDecryption.keyIndex(Data(count: size)) }
            #expect(throws: (any Error).self) { try ArchiveCompression.unpack(Data(count: size), expectedSize: 0) }
        }
        #expect(throws: MDictError.unsupported("block encryption method 3")) {
            try ArchiveCompression.unpack(Data([0x32, 16, 0, 0, 0, 0, 0, 1]), expectedSize: 0)
        }
        #expect(throws: MDictError.malformed("block checksum or size mismatch")) {
            // Empty fast-encrypted block with deliberately incorrect checksum.
            try ArchiveCompression.unpack(Data([0x10, 16, 0, 0, 0, 0, 0, 2]), expectedSize: 0)
        }
        #expect(throws: MDictError.malformed("fast decryption key")) { try ArchiveDecryption.fast(Data([1]), key: Data()) }
        #expect(throws: MDictError.malformed("Salsa20 key")) { try ArchiveDecryption.salsa20(Data([1]), key: Data(count: 15)) }
        #expect(throws: MDictError.malformed("Salsa20 nonce")) {
            try ArchiveDecryption.salsa20(Data([1]), key: Data(count: 16), nonce: Data(count: 7))
        }
        var key = [UInt8](repeating: 0, count: 16)
        #expect(folio_ripemd128(nil, 1, &key) == -1)
        #expect(folio_ripemd128(nil, 0, nil) == -1)
        #expect(folio_mdict_fast_decrypt(nil, 1, &key, 16) == -1)
        #expect(folio_mdict_fast_decrypt(nil, 0, &key, 0) == -1)
        #expect(folio_salsa20_8_xor(nil, 0, &key, 16, nil, 0) == -1)
    }
}
