import Foundation
import Testing
@testable import FolioCore

struct MultiDictionaryTests {
    @Test func queriesOverlapAndReturnInPriorityOrder() async throws {
        let gate = QueryGate(expected: 3)
        let local = MultipleSources(gate: gate)
        let online = ConcurrentOnline(gate: gate)
        let settings = MemoryDictionarySelectionStore(.init(priority: ["b", "youdao-online", "a"]))
        let coordinator = DictionaryLookupCoordinator(local: local, online: online, selection: settings)
        let report = try await coordinator.lookupAll("word")
        #expect(await gate.peak == 3)
        #expect(report.results.map(\.id) == ["b", "youdao-online", "a"])
        #expect(report.results.map(\.entry.dictionaryID) == ["b", "youdao-online", "a"])
        #expect(report.failures.isEmpty)
    }

    @Test func searchAlsoQueriesEnabledSourcesAndPreservesOrder() async throws {
        let gate = QueryGate(expected: 3)
        let coordinator = DictionaryLookupCoordinator(local: MultipleSources(gate: gate), online: ConcurrentOnline(gate: gate),
            selection: MemoryDictionarySelectionStore(.init(priority: ["b", "a", "youdao-online"])))
        let report = try await coordinator.searchReport("word")
        #expect(await gate.peak == 3)
        #expect(report.entries.map(\.dictionaryID) == ["b", "a", "youdao-online"])
    }

    @Test func disabledSourcesAreNeverContactedAndChangesApplyToNextQuery() async throws {
        let gate = QueryGate(expected: 1)
        let settings = MemoryDictionarySelectionStore(.init(disabledIDs: ["a", "youdao-online"]))
        let coordinator = DictionaryLookupCoordinator(local: MultipleSources(gate: gate), online: ConcurrentOnline(gate: gate), selection: settings)
        #expect(try await coordinator.lookupAll("word").results.map(\.id) == ["b"])
        #expect(await gate.ids == ["b"])
        #expect(try await coordinator.lookup("word", dictionaryID: "a") == nil)
        #expect(try await coordinator.entry(id: YoudaoEntryIdentity.id(for: "word")) == nil)
        try await settings.setEnabled(false, id: "b")
        #expect(try await coordinator.lookupAll("word").sources.isEmpty)
        #expect(try await coordinator.search("").isEmpty)
        try await settings.setEnabled(true, id: "a")
        #expect(try await coordinator.lookupAll("word").results.map(\.id) == ["a"])
    }

    @Test func oneFailurePreservesOtherResultsAndMissingEntriesStayEmpty() async throws {
        let coordinator = DictionaryLookupCoordinator(local: MultipleSources(failedID: "b"), online: OfflineOnline())
        let report = try await coordinator.lookupAll("word")
        #expect(report.results.map(\.id) == ["a"])
        #expect(report.failures.map(\.id) == ["b", "youdao-online"])
        #expect(report.failures.last?.message == YoudaoError.offline.message)
        let empty = try await coordinator.lookupAll("missing")
        #expect(empty.results.isEmpty)
        #expect(empty.failures.count == 2)
    }

    @Test func cancellationPropagatesWithoutBecomingSourceFailure() async throws {
        let coordinator = DictionaryLookupCoordinator(local: MultipleSources(), online: CancelledOnline())
        await #expect(throws: CancellationError.self) { try await coordinator.lookupAll("word") }
        let task = Task { try await coordinator.searchReport("word") }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func selectionSurvivesReopeningAndConcurrentToggles() async throws {
        let suite = "Folio.MultiTests.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = UserDefaultsDictionarySelectionStore(suiteName: suite)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ["a", "b", "youdao-online"] { group.addTask { try await store.setEnabled(false, id: id) } }
            try await group.waitForAll()
        }
        try await store.reorder(["b", "b", "a", "youdao-online"])
        let reopened = UserDefaultsDictionarySelectionStore(suiteName: suite)
        let preferences = await reopened.configuration()
        #expect(preferences.priority == ["b", "a", "youdao-online"])
        #expect(preferences.disabledIDs == ["a", "b", "youdao-online"])
        try await reopened.setEnabled(true, id: "b")
        #expect(await store.configuration().isEnabled("b"))
    }

    @Test func sourceSpecificFTSDoesNotLeakOtherDictionaries() async throws {
        let library = try DictionaryLibrary(path: ":memory:")
        try await library.seedSamples()
        let fixture = try #require(Bundle.module.url(forResource: "tiny", withExtension: "mdx", subdirectory: "Fixtures"))
        try await library.importArchives([fixture])
        let source = try #require(try await library.sources().first { !$0.isSample })
        #expect(try await library.search("", dictionaryID: source.id).allSatisfy { $0.dictionaryID == source.id })
        #expect(try await library.search("aur", dictionaryID: source.id).first?.headword == "aurora")
        #expect(try await library.search("aur", dictionaryID: "folio-sample").isEmpty)
    }
}

private actor QueryGate {
    let expected: Int
    private(set) var peak = 0
    private(set) var ids: Set<String> = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private var timeout: Task<Void, Never>?
    init(expected: Int) { self.expected = expected }
    func enter(_ id: String) async {
        ids.insert(id)
        guard !released else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            peak = max(peak, waiters.count)
            if waiters.count == expected { release() }
            else if timeout == nil {
                timeout = Task { do { try await Task.sleep(for: .seconds(2)) } catch { return }; release() }
            }
        }
    }
    private func release() {
        released = true; timeout?.cancel()
        let pending = waiters; waiters = []
        pending.forEach { $0.resume() }
    }
}

private struct MultipleSources: DictionaryRepository {
    var gate: QueryGate? = nil
    var failedID: String? = nil
    func sources() async -> [DictionarySource] { ["a", "b"].map { .init(id: $0, title: $0, filename: $0, entryCount: 1) } }
    func search(_ query: String) async throws -> [DictionaryEntry] { [] }
    func search(_ query: String, dictionaryID: String) async throws -> [DictionaryEntry] {
        try await lookup(query, dictionaryID: dictionaryID).map { [$0] } ?? []
    }
    func lookup(_ word: String, dictionaryID: String) async throws -> DictionaryEntry? {
        await gate?.enter(dictionaryID)
        if dictionaryID == failedID { throw MDictError.malformed("truncated file") }
        return word == "word" ? .init(id: dictionaryID + ":word", dictionaryID: dictionaryID, headword: word, summary: dictionaryID) : nil
    }
    func entry(id: String) async -> DictionaryEntry? { nil }
    func resource(path: String, dictionaryID: String) async -> Data? { nil }
}
private struct ConcurrentOnline: OnlineDictionaryService {
    let gate: QueryGate
    func lookup(_ word: String) async -> DictionaryEntry? {
        await gate.enter("youdao-online")
        return .init(id: "youdao-online:word", dictionaryID: "youdao-online", headword: word, summary: "online")
    }
}
private struct OfflineOnline: OnlineDictionaryService {
    func lookup(_ word: String) async throws -> DictionaryEntry? { throw YoudaoError.offline }
}
private struct CancelledOnline: OnlineDictionaryService {
    func lookup(_ word: String) async throws -> DictionaryEntry? { throw CancellationError() }
}
