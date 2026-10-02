import Foundation

public struct DictionaryEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let dictionaryID: String
    public let headword: String
    public let pronunciation: String
    public let partOfSpeech: String
    public let summary: String
    public let example: String
    public let html: String
    public let online: OnlineDefinition?

    public init(id: String, dictionaryID: String = "folio-sample", headword: String,
                pronunciation: String = "", partOfSpeech: String = "",
                summary: String, example: String = "", html: String = "", online: OnlineDefinition? = nil) {
        self.id = id
        self.dictionaryID = dictionaryID
        self.headword = headword
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.summary = summary
        self.example = example
        self.html = html
        self.online = online
    }

    // Navigation and list identity never hash potentially large definition HTML.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The dedicated Youdao dictionary API disallows retaining its returned content.
    /// Preserve the user's word as a bookmark, then fetch the definition when opened.
    public var vocabularySnapshot: Self {
        guard online?.allowsContentPersistence == false else { return self }
        return Self(id: id, dictionaryID: dictionaryID, headword: headword,
                    summary: "Open this word to look up its online definition.")
    }
}

public struct DictionarySource: Identifiable, Hashable, Sendable {
    public static let youdao = Self(id: "youdao-online", title: "Youdao", filename: "", entryCount: 0)
    public var isOnline: Bool { id == Self.youdao.id }
    public let id: String
    public let title: String
    public let filename: String
    public let entryCount: Int
    public let resourceCount: Int
    public let isSample: Bool

    public init(id: String, title: String, filename: String, entryCount: Int,
                resourceCount: Int = 0, isSample: Bool = false) {
        self.id = id
        self.title = title
        self.filename = filename
        self.entryCount = entryCount
        self.resourceCount = resourceCount
        self.isSample = isSample
    }
}

public protocol DictionaryRepository: Sendable {
    func search(_ query: String) async throws -> [DictionaryEntry]
    func search(_ query: String, dictionaryID: String) async throws -> [DictionaryEntry]
    func searchReport(_ query: String) async throws -> DictionarySearchReport
    func lookupAll(_ headword: String) async throws -> DictionaryLookupReport
    func entry(id: String) async throws -> DictionaryEntry?
    func lookup(_ headword: String, dictionaryID: String) async throws -> DictionaryEntry?
    func sources() async throws -> [DictionarySource]
    func resource(path: String, dictionaryID: String) async throws -> Data?
}

public extension DictionaryRepository {
    func search(_ query: String, dictionaryID: String) async throws -> [DictionaryEntry] {
        try await search(query).filter { $0.dictionaryID == dictionaryID }
    }
    func searchReport(_ query: String) async throws -> DictionarySearchReport {
        DictionarySearchReport(entries: try await search(query))
    }
    func lookupAll(_ headword: String) async throws -> DictionaryLookupReport {
        let sources = try await sources()
        let repository = self
        let outcomes = try await withThrowingTaskGroup(of: (DictionaryLookupResult?, DictionarySourceFailure?).self) { group in
            for source in sources {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let entry = try await repository.lookup(headword, dictionaryID: source.id)
                        try Task.checkCancellation()
                        return (entry.map { DictionaryLookupResult(source: source, entry: $0) }, nil)
                    } catch is CancellationError { throw CancellationError() }
                    catch { return (nil, DictionarySourceFailure(source: source, message: .from(error, fallback: "This dictionary couldn’t be queried. Please try again."))) }
                }
            }
            var values: [(DictionaryLookupResult?, DictionarySourceFailure?)] = []
            for try await value in group { values.append(value) }
            return values
        }
        try Task.checkCancellation()
        return DictionaryLookupReport(sources: sources,
            results: sources.compactMap { source in outcomes.compactMap(\.0).first { $0.source.id == source.id } },
            failures: sources.compactMap { source in outcomes.compactMap(\.1).first { $0.source.id == source.id } })
    }
}
