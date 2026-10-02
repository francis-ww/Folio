import Foundation
import Testing
@testable import FolioCore

struct DictionaryLibraryTests {
    private func fixture(_ name: String, _ ext: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    @Test func importsDefinitionsAliasesAndCrossBlockResources() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.importArchives([fixture("tiny", "mdd"), fixture("tiny", "mdx")])
        let sources = try await library.sources()
        let source = try #require(sources.first)
        #expect(source.entryCount == 4)
        #expect(source.resourceCount == 2)
        let results = try await library.search("aur")
        #expect(results.map(\.headword) == ["aurora"])
        #expect(results.first?.html.contains("—") == true)
        let alias = try await library.lookup("alias", dictionaryID: source.id)
        #expect(alias?.html == results.first?.html)
        let redirect = try await library.lookup("redirect", dictionaryID: source.id)
        #expect(redirect?.headword == "aurora")
        let image = try #require(try await library.resource(path: "/IMAGES/leaf.png", dictionaryID: source.id))
        #expect(Array(image.prefix(4)) == [137, 80, 78, 71])
        let sound = try #require(try await library.resource(path: "\\sound\\word.wav", dictionaryID: source.id))
        #expect(String(data: sound.prefix(4), encoding: .ascii) == "RIFF")
    }

    @Test func failedImportRollsBackAllSelectedFiles() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.seedSamples()
        do {
            try await library.importArchives([fixture("tiny", "mdx"), fixture("broken", "mdd")])
            Issue.record("Expected a malformed archive error")
        } catch {}
        #expect(try await library.sources().count == 1)
        #expect(try await library.search("aurora").isEmpty)
        #expect(try await library.search("serendipity").count == 1)
    }

    @Test func replacingAndRemovingDictionaryKeepIndexConsistent() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        let url = try fixture("tiny", "mdx")
        try await library.importArchives([url])
        let originalID = try #require(try await library.sources().first?.id)
        try await library.importArchives([url])
        let source = try #require(try await library.sources().first)
        #expect(source.id == originalID)
        #expect(try await library.sources().count == 1)
        #expect(try await library.search("aurora").count == 1)
        try await library.removeSource(id: source.id)
        #expect(try await library.search("aurora").isEmpty)
        #expect(try await library.sources().isEmpty)
    }

    @Test func failedReplacementPreservesPreviousDictionaryAndResources() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        let mdx = try fixture("tiny", "mdx")
        try await library.importArchives([mdx, fixture("tiny", "mdd")])
        let previous = try await library.sources()
        do {
            try await library.importArchives([mdx, fixture("broken", "mdd")])
            Issue.record("Expected failed replacement")
        } catch {}
        #expect(try await library.sources() == previous)
        #expect(try await library.search("aurora").count == 1)
        let source = try #require(previous.first)
        #expect(try await library.resource(path: "/images/leaf.png", dictionaryID: source.id) != nil)
    }

    @Test func streamingStopsAfterCancellationDuringConsumption() async throws {
        let url = try fixture("tiny", "mdx")
        let task = Task {
            let reader = try MDictReader(url: url, resourceArchive: false)
            try reader.records { _, _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        do { try await task.value; Issue.record("Expected streaming cancellation") }
        catch is CancellationError {}
    }

    @Test func uncompressedArchiveIsSupported() throws {
        let reader = try MDictReader(url: fixture("uncompressed", "mdx"), resourceArchive: false)
        var entries: [String] = []
        try reader.records { name, _ in entries.append(name) }
        #expect(entries == ["alias", "aurora", "bloom", "redirect"])
    }

    @Test(arguments: ["encrypted", "old-version", "corrupt", "truncated"])
    func rejectsUnsupportedAndDamagedArchives(_ name: String) throws {
        let url = try fixture(name, "mdx")
        #expect(throws: (any Error).self) {
            let reader = try MDictReader(url: url, resourceArchive: false)
            try reader.records { _, _ in }
        }
    }

    @Test func cancellationDoesNotCommit() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        let url = try fixture("tiny", "mdx")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await library.importArchives([url])
        }
        do { try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError {}
        #expect(try await library.sources().isEmpty)
    }

    @Test(arguments: ["\"", "* OR NOT", "a'b", "NEAR(x)", "(bloom)", "🤍"])
    func searchTreatsInputAsLiteralText(_ text: String) async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.seedSamples()
        _ = try await library.search(text)
    }

    @Test func resourcePathsAreNormalizedAndBounded() {
        #expect(ResourcePath.normalize("\\Images\\Leaf.PNG") == "/images/leaf.png")
        #expect(ResourcePath.normalize("/a/%2E%2E/secret") == nil)
        #expect(ResourcePath.normalize("file:///etc/passwd") == nil)
        #expect(ResourcePath.normalize("/a\0b") == nil)
        #expect(ResourcePath.mimeType("/word.wav") == "audio/wav")
    }
}
