import Foundation
import Testing
import FolioArchive
import GRDB
@testable import FolioCore

struct MassiveArchiveTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.MassiveTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func indexesValidSparseMDDAndReadsResourceBeyondTwoGigabytes() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("OxfordV3.mdx"))
        let mdd = root.appendingPathComponent("Oxford3.mdd")
        let tail = Data("RIFFtestWAVE".utf8)
        try SparseMDictFixture.writeResource(to: mdd, padding: 2_400_000_000, tail: tail)
        let file = try ArchiveFile(url: mdd)
        #expect(file.length > UInt64(Int32.max))
        try file.seek(to: file.length - UInt64(tail.count))
        #expect(try file.read(tail.count) == tail)

        let library = try DictionaryLibrary(path: root.appendingPathComponent("library.sqlite").path)
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        let progress = DefinitionReadinessProbe()
        let report = try await scanner.scan {
            if let source = try? await library.sources().first, source.resourceCount == 0,
               (try? await library.lookup("aurora", dictionaryID: source.id)) != nil {
                await progress.record()
            }
        }
        #expect(report.updatedCount == 1 && report.failures.isEmpty)
        #expect(await progress.count > 0) // Reading was available before MDD publication.
        let source = try #require(try await library.sources().first)
        #expect(source.entryCount == 4 && source.resourceCount == 2)
        #expect(try await library.resource(path: "/sound/word.wav", dictionaryID: source.id) == tail)
        let filenames = try await library.indexFiles(sourceID: source.id)
        let indexRoot = await library.indexRoot
        var indexBytes: UInt64 = 0
        for filename in filenames {
            let url = indexRoot.appendingPathComponent(filename)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            indexBytes += (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        }
        #expect(indexBytes < 1_024 * 1_024) // No 2.4 GB resource copy in SQLite.
        let resourceFile = try #require(filenames.last)
        let index = try MDictIndexDatabase(url: indexRoot.appendingPathComponent(resourceFile))
        let offset = try index.read { db in try Int64.fetchOne(db, sql: "SELECT max(fileOffset) FROM blocks") }
        #expect(try #require(offset) > Int64(Int32.max))
        do {
            _ = try await library.resource(path: "/padding.bin", dictionaryID: source.id)
            Issue.record("Expected an oversized individual resource guard")
        } catch let error as MDictError { #expect(error == .limitExceeded) }
    }

    @Test func keywordsArePersistedInBoundedBatchesAndDefinitionsRemainSearchable() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Many.mdx")
        try SparseMDictFixture.writeDefinitions(to: url, count: 5_500)
        let reader = try MDictReader(url: url, resourceArchive: false)
        var previous = 0, batches = 0, more = true
        while more {
            more = try reader.indexNextBatch()
            let count = try reader.index.read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM keys") ?? 0 }
            #expect(count - previous <= MDictReader.batchSize)
            previous = count; batches += 1
        }
        #expect(previous == 5_500 && batches >= 6)
        let library = try DictionaryLibrary(path: root.appendingPathComponent("library.sqlite").path)
        try await library.importArchives([url])
        let source = try #require(try await library.sources().first)
        #expect(source.entryCount == 5_500)
        #expect(try await library.lookup("word05499", dictionaryID: source.id)?.html == "<p>A shared definition.</p>")
        #expect(try await library.search("word05499").first?.headword == "word05499")
    }

    @Test func pairsVersionNamesAndUniquePrefixesAndRejectsAmbiguousResources() {
        #expect(DictionaryFilePairing.match(resourceStem: "Oxford3", dictionaryStems: ["oxfordv3", "collins"]) == "oxfordv3")
        #expect(DictionaryFilePairing.match(resourceStem: "Oxford-v3-resources", dictionaryStems: ["oxford3", "collins"]) == "oxford3")
        #expect(DictionaryFilePairing.match(resourceStem: "Oxford", dictionaryStems: ["Oxford2", "Oxford3"]) == nil)
        #expect(DictionaryFilePairing.match(resourceStem: "Oxford3", dictionaryStems: ["Oxford3", "OxfordV3"]) == "Oxford3")
        #expect(DictionaryFilePairing.match(resourceStem: "resources", dictionaryStems: ["sole-dictionary"]) == "sole-dictionary")
    }

    @Test func offsetsOverflowAndCInvalidPointersProduceErrors() throws {
        #expect(try MDictBounds.add(2_400_000_000, 64_000) == 2_400_064_000)
        #expect(throws: MDictError.limitExceeded) { try MDictBounds.add(UInt64.max, 1) }
        #expect(throws: MDictError.limitExceeded) { try MDictBounds.sqlite(UInt64.max) }
        var output: UInt8 = 0
        var capacity: UInt64 = 1
        #expect(folio_inflate(nil, 1, &output, &capacity) != 0)
        #expect(folio_inflate(nil, 0, nil, nil) != 0)
        #expect(folio_adler32(nil, 1) == 0)
        var cursor = BinaryCursor(data: Data([0]))
        #expect(throws: MDictError.malformed("integer width")) { try cursor.integer(9) }
    }

    @Test func corruptLazyResourceThrowsAndDefinitionsRemainAvailable() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mdx = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        let mdd = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdd", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: mdx, to: root.appendingPathComponent("Test.mdx"))
        var damaged = try Data(contentsOf: mdd)
        damaged[damaged.count - 1] ^= 0xff
        try damaged.write(to: root.appendingPathComponent("Test.mdd"))
        let library = try DictionaryLibrary(path: root.appendingPathComponent("library.sqlite").path)
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        #expect(try await scanner.scan().updatedCount == 1)
        let source = try #require(try await library.sources().first)
        do {
            _ = try await library.resource(path: "/sound/word.wav", dictionaryID: source.id)
            Issue.record("Expected a guarded resource checksum/decompression failure")
        } catch let error as MDictError {
            #expect(error.message.key == "This dictionary is damaged or invalid: %@.")
        }
        #expect(try await library.lookup("aurora", dictionaryID: source.id) != nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Test.mdd"))
        do {
            _ = try await library.resource(path: "/images/leaf.png", dictionaryID: source.id)
            Issue.record("Expected a guarded missing-archive error")
        } catch let error as DocumentsDictionaryError { #expect(error == .unreadableFile("Test.mdd")) }
    }

    @Test func deletedDictionaryResourceIsNotReassignedToTheRemainingDictionary() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let mdx = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        let mdd = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdd", subdirectory: "Fixtures"))
        for name in ["Oxford", "Collins"] {
            try FileManager.default.copyItem(at: mdx, to: root.appendingPathComponent(name + ".mdx"))
        }
        try FileManager.default.copyItem(at: mdd, to: root.appendingPathComponent("Oxford.mdd"))
        let library = try DictionaryLibrary(path: root.appendingPathComponent("library.sqlite").path)
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        _ = try await scanner.scan()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Oxford.mdx"))
        let report = try await scanner.scan()
        #expect(report.removedCount == 1 && report.failures.count == 1)
        let remaining = try #require(try await library.sources().first)
        #expect(remaining.filename == "collins" && remaining.resourceCount == 0)
    }
}

private actor DefinitionReadinessProbe {
    private(set) var count = 0
    func record() { count += 1 }
}

/// Original valid v2 fixtures. Huge payloads are holes in a sparse file, not giant Data values.
private enum SparseMDictFixture {
    static func integer(_ value: UInt64, width: Int = 8, littleEndian: Bool = false) -> Data {
        let shifts = littleEndian ? Array(0..<width) : Array((0..<width).reversed())
        return Data(shifts.map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    static func block(_ bytes: Data) -> Data {
        integer(0, width: 4, littleEndian: true) + integer(UInt64(ArchiveCompression.checksum(bytes)), width: 4) + bytes
    }
    static func prefix(names: [String], offsets: [UInt64], resource: Bool) -> Data {
        let xml = "<Dictionary GeneratedByEngineVersion=\"2.0\" Encoding=\"UTF-8\" Encrypted=\"No\" Title=\"Original sparse fixture\"/>\0"
        let header = xml.data(using: .utf16LittleEndian)!
        var output = integer(UInt64(header.count), width: 4) + header + integer(UInt64(ArchiveCompression.checksum(header)), width: 4, littleEndian: true)
        let encoding: String.Encoding = resource ? .utf16LittleEndian : .utf8
        let width = resource ? 2 : 1
        var rawKeys = Data()
        for (name, offset) in zip(names, offsets) { rawKeys += integer(offset) + name.data(using: encoding)! + Data(count: width) }
        let keys = block(rawKeys)
        var info = integer(UInt64(names.count))
        for name in [names.first!, names.last!] {
            let bytes = name.data(using: encoding)!
            info += integer(UInt64(bytes.count / width), width: 2) + bytes + Data(count: width)
        }
        info += integer(UInt64(keys.count)) + integer(UInt64(rawKeys.count))
        let packed = block(info)
        let metadata = integer(1) + integer(UInt64(names.count)) + integer(UInt64(info.count)) + integer(UInt64(packed.count)) + integer(UInt64(keys.count))
        output += metadata + integer(UInt64(ArchiveCompression.checksum(metadata)), width: 4) + packed + keys
        return output
    }
    static func writeDefinitions(to url: URL, count: Int) throws {
        let names = (0..<count).map { String(format: "word%05d", $0) }
        let bytes = Data("<p>A shared definition.</p>\0".utf8)
        let record = block(bytes)
        let info = integer(UInt64(record.count)) + integer(UInt64(bytes.count))
        let metadata = integer(1) + integer(UInt64(count)) + integer(UInt64(info.count)) + integer(UInt64(record.count))
        try (prefix(names: names, offsets: Array(repeating: 0, count: count), resource: false) + metadata + info + record).write(to: url)
    }
    static func writeResource(to url: URL, padding: UInt64, tail: Data) throws {
        let chunk: UInt64 = 8 * 1_024 * 1_024
        var sizes: [UInt64] = []
        var remaining = padding
        while remaining > 0 { let count = min(chunk, remaining); sizes.append(count); remaining -= count }
        var info = Data()
        for size in sizes { info += integer(size + 8) + integer(size) }
        info += integer(UInt64(tail.count + 8)) + integer(UInt64(tail.count))
        let metadata = integer(UInt64(sizes.count + 1)) + integer(2) + integer(UInt64(info.count)) + integer(padding + UInt64(sizes.count * 8 + tail.count + 8))
        try (prefix(names: ["\\padding.bin", "\\sound\\word.wav"], offsets: [0, padding], resource: true) + metadata + info).write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var position = try handle.seekToEnd()
        for size in sizes {
            // Adler-32 of n zero bytes: s1=1, s2=n mod 65521.
            let checksum = ((size % 65_521) << 16) | 1
            try handle.write(contentsOf: integer(0, width: 4) + integer(checksum, width: 4))
            position += 8 + size
            try handle.seek(toOffset: position)
        }
        try handle.write(contentsOf: block(tail))
    }
}
