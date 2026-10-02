import Foundation
import Testing
@testable import FolioCore

struct DocumentsDictionaryScannerTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.DocumentsTests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copy(_ name: String = "tiny", ext: String, to root: URL, as filename: String? = nil) throws {
        let fixture = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent(filename ?? "Reference.\(ext)"))
    }

    @Test func pairsCaseInsensitiveNamesAndSkipsUnchangedFilesAfterRestart() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("index.sqlite").path
        let library = try DictionaryLibrary(path: database)
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root, as: "Reference.MDX")
        try copy(ext: "mdd", to: root, as: "reference.mdd")
        let first = try await scanner.scan()
        #expect(first.discoveredCount == 1 && first.updatedCount == 1 && first.failures.isEmpty)
        let source = try #require(try await library.sources().first)
        #expect(source.entryCount == 4 && source.resourceCount == 2)
        #expect(try await library.lookup("aurora", dictionaryID: source.id)?.html.contains("—") == true)
        #expect(try await library.resource(path: "/sound/word.wav", dictionaryID: source.id) != nil)
        let reopened = try DictionaryLibrary(path: database)
        let next = try DocumentsDictionaryScanner(root: root, library: reopened)
        let unchanged = try await next.scan()
        #expect(unchanged.updatedCount == 0 && unchanged.unchangedCount == 1 && unchanged.failures.isEmpty)
        #expect(try await reopened.sources() == [source])
    }

    @Test func addingReplacingAndRemovingMDDKeepsEntriesAndClearsStaleResources() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        _ = try await scanner.scan()
        let initial = try #require(try await library.sources().first)
        let entry = try #require(try await library.lookup("aurora", dictionaryID: initial.id))
        try copy(ext: "mdd", to: root)
        #expect(try await scanner.scan().updatedCount == 1)
        #expect(try await library.sources().first?.resourceCount == 2)
        // Replacing an MDD rebuilds resources rather than retaining deleted paths.
        try FileManager.default.removeItem(at: root.appendingPathComponent("Reference.mdd"))
        try copy("revised", ext: "mdd", to: root)
        #expect(try await scanner.scan().updatedCount == 1)
        #expect(try await library.sources().first?.resourceCount == 1)
        #expect(try await library.resource(path: "/sound/word.wav", dictionaryID: initial.id) == nil)
        #expect(try await library.lookup("aurora", dictionaryID: initial.id) == entry)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Reference.mdd"))
        #expect(try await scanner.scan().updatedCount == 1)
        #expect(try await library.sources().first?.resourceCount == 0)
        #expect(try await library.resource(path: "/images/leaf.png", dictionaryID: initial.id) == nil)
        #expect(try await library.lookup("aurora", dictionaryID: initial.id) == entry)
    }

    @Test func damagedReplacementRollsBackAndRemainsRetryable() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy(ext: "mdd", to: root)
        _ = try await scanner.scan()
        let previous = try await library.sources()
        let mdd = root.appendingPathComponent("Reference.mdd")
        try FileManager.default.removeItem(at: mdd)
        try copy("broken", ext: "mdd", to: root)
        let failed = try await scanner.scan()
        #expect(failed.updatedCount == 0 && failed.failures.count == 1)
        #expect(try await library.sources() == previous)
        #expect(try await scanner.scan().failures.count == 1)
        try FileManager.default.removeItem(at: mdd)
        try copy(ext: "mdd", to: root)
        let recovered = try await scanner.scan()
        #expect(recovered.updatedCount == 1 && recovered.failures.isEmpty)
        #expect(try await library.sources() == previous)
    }

    @Test func replacingMDXRebuildsIndexAndPreservesSourceID() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy(ext: "mdd", to: root)
        _ = try await scanner.scan()
        let original = try #require(try await library.sources().first)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Reference.mdx"))
        try copy("revised", ext: "mdx", to: root)
        #expect(try await scanner.scan().updatedCount == 1)
        let updated = try #require(try await library.sources().first)
        #expect(updated.id == original.id && updated.entryCount == 2 && updated.resourceCount == 2)
        #expect(try await library.search("bloom").isEmpty)
        #expect(try await library.lookup("aurora", dictionaryID: original.id)?.summary == "The first light of dawn.")
        #expect(try await library.search("zenith").count == 1)
        #expect(try await scanner.scan().unchangedCount == 1)
    }

    @Test func fileChangedAfterDiscoveryIsNotCommitted() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        try copy(ext: "mdx", to: root)
        let url = root.appendingPathComponent("Reference.mdx")
        let snapshot = try DocumentsArchiveSnapshot(stem: "reference", mdx: ArchiveFileStamp.read(url, root: root), mdd: nil)
        try Data("copy still in progress".utf8).write(to: url, options: .atomic)
        do {
            _ = try await library.synchronizeDocumentsArchive(snapshot, root: root)
            Issue.record("Expected changed-file detection")
        } catch let error as DocumentsDictionaryError { #expect(error == .changingFile) }
        #expect(try await library.sources().isEmpty)
    }

    @Test func malformedPairDoesNotBlockOtherDictionariesAndOrphansAreReported() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy("corrupt", ext: "mdx", to: root, as: "Broken.mdx")
        try copy(ext: "mdd", to: root, as: "Orphan.mdd")
        let report = try await scanner.scan()
        #expect(report.discoveredCount == 2 && report.updatedCount == 1 && report.failures.count == 2)
        #expect(try await library.sources().count == 1)
        #expect(try await library.search("aurora").count == 1)
    }

    @Test func filesDeletionRemovesManagedIndexButRetainsLegacyAndSampleSources() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.seedSamples()
        let legacy = try #require(Bundle.module.url(forResource: "uncompressed", withExtension: "mdx", subdirectory: "Fixtures"))
        try await library.importArchives([legacy])
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy(ext: "mdd", to: root)
        _ = try await scanner.scan()
        try FileManager.default.removeItem(at: root.appendingPathComponent("Reference.mdx"))
        let report = try await scanner.scan()
        #expect(report.removedCount == 1)
        #expect(try await library.sources().map(\.filename).sorted() == ["sample", "uncompressed"])
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Reference.mdd").path))
    }

    @Test func removalDeletesOwnedArchivePairAndDoesNotReappearOnScan() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy(ext: "mdd", to: root)
        _ = try await scanner.scan()
        let id = try #require(try await library.sources().first?.id)
        try await scanner.removeDictionary(id: id)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Reference.mdx").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Reference.mdd").path))
        #expect(try await scanner.scan().discoveredCount == 0)
        #expect(try await library.sources().isEmpty)
    }

    @Test func ignoresSubfoldersAndUnrelatedFilesAndRejectsSymbolicLinks() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let subfolder = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try copy(ext: "mdx", to: subfolder)
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        #expect(try await scanner.scan().discoveredCount == 0)
        let target = subfolder.appendingPathComponent("Reference.mdx")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.mdx"), withDestinationURL: target)
        let report = try await scanner.scan()
        #expect(report.updatedCount == 0 && report.failures.count == 1)
        #expect(try await library.sources().isEmpty)
        #expect(throws: DocumentsDictionaryError.unsafeFile) { try ArchiveFileAccess.delete(root.appendingPathComponent("Linked.mdx"), root: root) }
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test func concurrentScansDoNotDuplicateSources() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        try copy(ext: "mdd", to: root)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<6 { group.addTask { _ = try await scanner.scan() } }
            try await group.waitForAll()
        }
        #expect(try await library.sources().count == 1)
        #expect(try await library.search("aurora").count == 1)
        #expect(try await scanner.scan().unchangedCount == 1)
    }

    @Test func gigabyteSparseMDDIsRejectedWithoutWholeFileLoading() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        try copy(ext: "mdx", to: root)
        let mdd = root.appendingPathComponent("Reference.mdd")
        #expect(FileManager.default.createFile(atPath: mdd.path, contents: nil))
        let handle = try FileHandle(forWritingTo: mdd)
        try handle.truncate(atOffset: 1_073_741_824)
        try handle.close()
        let report = try await scanner.scan()
        #expect(report.failures.count == 1 && report.updatedCount == 0)
        #expect(try await library.sources().isEmpty) // The entire pair rolls back.
    }
}
