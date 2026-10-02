import Foundation
import Testing
@testable import FolioCore

struct DictionaryLookupCoordinatorTests {
    private func installedLibrary() async throws -> DictionaryLibrary {
        let library = try DictionaryLibrary(path: ":memory:")
        let fixture = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        try await library.importArchives([fixture])
        try await library.seedSamples()
        return library
    }

    @Test func localMDXMatchesLeadAlongsideEnabledOnlineSource() async throws {
        let local = try await installedLibrary()
        let online = LookupSpy()
        let coordinator = DictionaryLookupCoordinator(local: local, online: online)
        let matches = try await coordinator.search("aur")
        #expect(matches.count == 2 && matches.first?.headword == "aurora")
        #expect(matches.first?.online == nil)
        let source = try #require(try await coordinator.sources().first { !$0.isSample })
        #expect(try await coordinator.lookup("aurora", dictionaryID: source.id)?.headword == "aurora")
        #expect(await online.queries == ["aur"])
    }

    @Test func emptyQueriesBrowseLocallyWithoutOnlineRequests() async throws {
        let online = LookupSpy()
        let coordinator = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: online)
        #expect(try await coordinator.search("  ").count == SampleData.entries.count)
        #expect(await online.queries.isEmpty)
    }

    @Test func samplesDoNotSuppressDefaultOnlineFallback() async throws {
        let online = LookupSpy()
        let coordinator = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: online)
        let entries = try await coordinator.search("ephemeral")
        #expect(entries.first?.online != nil)
        #expect(await online.queries == ["ephemeral"])
    }

    @Test func missingLocalWordsFallBackEvenWithInstalledMDX() async throws {
        let online = LookupSpy()
        let local = try await installedLibrary()
        let coordinator = DictionaryLookupCoordinator(local: local, online: online)
        #expect(try await coordinator.search("ephemeral").first?.online != nil)
        let source = try #require(try await local.sources().first { !$0.isSample })
        #expect(try await coordinator.lookup("ephemeral", dictionaryID: source.id) == nil)
        #expect(try await coordinator.lookupAll("ephemeral").results.first?.entry.online != nil)
        #expect(await online.queries == ["ephemeral", "ephemeral"])
    }

    @Test func deletingLastMDXRestoresOnlineFallback() async throws {
        let online = LookupSpy()
        let local = try await installedLibrary()
        let coordinator = DictionaryLookupCoordinator(local: local, online: online)
        let source = try #require(try await local.sources().first { !$0.isSample })
        try await local.removeSource(id: source.id)
        _ = try await coordinator.search("aurora")
        #expect(await online.queries == ["aurora"])
    }

    @Test func onlineIdentityRestoresBookmarksWithoutCachingResults() async throws {
        let online = LookupSpy()
        let coordinator = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: online)
        let id = YoudaoEntryIdentity.id(for: "a+b / 汉字")
        #expect(YoudaoEntryIdentity.word(from: id) == "a+b / 汉字")
        _ = try await coordinator.entry(id: id)
        _ = try await coordinator.entry(id: id)
        #expect(await online.queries == ["a+b / 汉字", "a+b / 汉字"])
    }

    @Test func networkErrorsStayVisibleAndNoMatchIsAnEmptyResult() async throws {
        let coordinator = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: FailingOnlineService())
        do { _ = try await coordinator.search("unlisted"); Issue.record("Expected offline error") }
        catch let error as DictionaryLookupError { #expect(error.message == YoudaoError.offline.message) }
        let empty = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: LookupSpy(entry: nil))
        #expect(try await empty.search("unlisted").isEmpty)
    }
}

private actor LookupSpy: OnlineDictionaryService {
    let result: DictionaryEntry?
    private(set) var queries: [String] = []
    init(entry: DictionaryEntry? = SampleData.onlineEntry) { result = entry }
    func lookup(_ word: String) -> DictionaryEntry? { queries.append(word); return result }
}
private struct FailingOnlineService: OnlineDictionaryService {
    func lookup(_ word: String) async throws -> DictionaryEntry? { throw YoudaoError.offline }
}
