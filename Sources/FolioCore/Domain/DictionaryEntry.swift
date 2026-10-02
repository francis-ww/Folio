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

    public init(id: String, dictionaryID: String = "folio-sample", headword: String,
                pronunciation: String = "", partOfSpeech: String = "",
                summary: String, example: String = "", html: String = "") {
        self.id = id
        self.dictionaryID = dictionaryID
        self.headword = headword
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.summary = summary
        self.example = example
        self.html = html
    }

    // Navigation and list identity never hash potentially large definition HTML.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct DictionarySource: Identifiable, Hashable, Sendable {
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
    func entry(id: String) async throws -> DictionaryEntry?
    func lookup(_ headword: String, dictionaryID: String) async throws -> DictionaryEntry?
    func sources() async throws -> [DictionarySource]
    func resource(path: String, dictionaryID: String) async throws -> Data?
}
