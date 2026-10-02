import Foundation

/// Every enabled source is queried independently. Completion order never changes
/// display priority, and a failed source cannot discard another source's result.
public actor DictionaryLookupCoordinator: DictionaryRepository {
    private let local: any DictionaryRepository
    private let online: any OnlineDictionaryService
    private let selection: any DictionarySelectionStore
    public init(local: any DictionaryRepository, online: any OnlineDictionaryService,
                selection: any DictionarySelectionStore = MemoryDictionarySelectionStore()) {
        self.local = local; self.online = online; self.selection = selection
    }
    public func sources() async throws -> [DictionarySource] {
        try await orderedSources(preferences: selection.configuration())
    }
    private func orderedSources(preferences: DictionarySelection) async throws -> [DictionarySource] {
        let sources = try await local.sources()
        return preferences.ordered(sources.filter { !$0.isSample && !$0.isOnline } + [.youdao] + sources.filter(\.isSample))
    }
    public func search(_ query: String) async throws -> [DictionaryEntry] {
        let report = try await searchReport(query)
        if report.entries.isEmpty, let failure = report.failures.first { throw DictionaryLookupError(message: failure.message) }
        return report.entries
    }
    public func searchReport(_ query: String) async throws -> DictionarySearchReport {
        let outcomes = try await querySources(query, exact: false)
        var seen: Set<String> = []
        return DictionarySearchReport(entries: outcomes.flatMap(\.entries).filter { seen.insert($0.id).inserted },
                                      failures: outcomes.compactMap(\.failure), sources: outcomes.map(\.source))
    }
    public func lookupAll(_ headword: String) async throws -> DictionaryLookupReport {
        let outcomes = try await querySources(headword, exact: true)
        return DictionaryLookupReport(sources: outcomes.map(\.source), results: outcomes.compactMap { outcome in
            outcome.entries.first.map { DictionaryLookupResult(source: outcome.source, entry: $0) }
        }, failures: outcomes.compactMap(\.failure))
    }
    public func lookup(_ headword: String, dictionaryID: String) async throws -> DictionaryEntry? {
        guard try await selection.configuration().isEnabled(dictionaryID) else { return nil }
        try Task.checkCancellation()
        if dictionaryID == DictionarySource.youdao.id { return try await online.lookup(headword) }
        return try await local.lookup(headword, dictionaryID: dictionaryID)
    }
    public func search(_ query: String, dictionaryID: String) async throws -> [DictionaryEntry] {
        guard try await selection.configuration().isEnabled(dictionaryID) else { return [] }
        if dictionaryID == DictionarySource.youdao.id {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return try await online.lookup(query).map { [$0] } ?? []
        }
        return try await local.search(query, dictionaryID: dictionaryID)
    }
    public func entry(id: String) async throws -> DictionaryEntry? {
        if let word = YoudaoEntryIdentity.word(from: id) { return try await lookup(word, dictionaryID: DictionarySource.youdao.id) }
        return try await local.entry(id: id)
    }
    public func resource(path: String, dictionaryID: String) async throws -> Data? {
        // Saved MDX snapshots still need resources even when lookup is disabled.
        try await local.resource(path: path, dictionaryID: dictionaryID)
    }
    private struct Outcome: Sendable {
        let source: DictionarySource
        let entries: [DictionaryEntry]
        let failure: DictionarySourceFailure?
    }
    private func querySources(_ query: String, exact: Bool) async throws -> [Outcome] {
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let preferences = try await selection.configuration()
        let enabled = try await orderedSources(preferences: preferences).filter { preferences.isEnabled($0.id) }
        try Task.checkCancellation()
        let local = self.local, online = self.online
        let values = try await withThrowingTaskGroup(of: Outcome.self) { group in
            for source in enabled {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let entries: [DictionaryEntry]
                        if source.isOnline {
                            entries = text.isEmpty ? [] : (try await online.lookup(text).map { [$0] } ?? [])
                        } else if exact {
                            entries = text.isEmpty ? [] : (try await local.lookup(text, dictionaryID: source.id).map { [$0] } ?? [])
                        } else {
                            entries = try await local.search(text, dictionaryID: source.id)
                        }
                        try Task.checkCancellation()
                        return Outcome(source: source, entries: entries, failure: nil)
                    } catch is CancellationError { throw CancellationError() }
                    catch {
                        return Outcome(source: source, entries: [], failure: .init(source: source,
                            message: .from(error, fallback: "This dictionary couldn’t be queried. Please try again.")))
                    }
                }
            }
            var result: [Outcome] = []
            for try await value in group { result.append(value) }
            return result
        }
        try Task.checkCancellation()
        return enabled.compactMap { source in values.first { $0.source.id == source.id } }
    }
}
