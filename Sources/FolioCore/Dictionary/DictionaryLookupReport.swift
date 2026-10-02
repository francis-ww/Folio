import Foundation

public struct DictionaryLookupResult: Identifiable, Sendable {
    public let source: DictionarySource
    public let entry: DictionaryEntry
    public var id: String { source.id }
    public init(source: DictionarySource, entry: DictionaryEntry) { self.source = source; self.entry = entry }
}
public struct DictionarySourceFailure: Identifiable, Sendable {
    public let source: DictionarySource
    public let message: FolioMessage
    public var id: String { source.id }
    public init(source: DictionarySource, message: FolioMessage) { self.source = source; self.message = message }
}
public struct DictionaryLookupReport: Sendable {
    public let sources: [DictionarySource]
    public let results: [DictionaryLookupResult]
    public let failures: [DictionarySourceFailure]
    public init(sources: [DictionarySource], results: [DictionaryLookupResult], failures: [DictionarySourceFailure] = []) {
        self.sources = sources; self.results = results; self.failures = failures
    }
}
public struct DictionarySearchReport: Sendable {
    public let entries: [DictionaryEntry]
    public let failures: [DictionarySourceFailure]
    public let sources: [DictionarySource]
    public init(entries: [DictionaryEntry], failures: [DictionarySourceFailure] = [], sources: [DictionarySource] = []) {
        self.entries = entries; self.failures = failures; self.sources = sources
    }
}
public struct DictionaryLookupError: LocalizedError, FolioMessageProviding {
    public let message: FolioMessage
    public init(message: FolioMessage) { self.message = message }
    public var errorDescription: String? { message.englishDescription }
}
