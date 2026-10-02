import Foundation

public actor MockDictionaryRepository: DictionaryRepository {
    public init() {}
    public func search(_ query: String) -> [DictionaryEntry] {
        SampleData.entries.filter { query.isEmpty || $0.headword.localizedCaseInsensitiveContains(query) }
    }
    public func entry(id: String) -> DictionaryEntry? { SampleData.entries.first { $0.id == id } }
    public func lookup(_ headword: String, dictionaryID: String) -> DictionaryEntry? {
        SampleData.entries.first { $0.dictionaryID == dictionaryID && $0.headword.lowercased() == headword.lowercased() }
    }
    public func sources() -> [DictionarySource] {
        [.init(id: "folio-sample", title: "Folio sample dictionary", filename: "sample", entryCount: SampleData.entries.count, isSample: true)]
    }
    public func resource(path: String, dictionaryID: String) -> Data? { nil }
}

public actor MockVocabularyRepository: VocabularyRepository {
    private var values: [VocabularyCard]
    public init(cards: [VocabularyCard] = SampleData.cards()) { values = cards }
    public func cards() -> [VocabularyCard] { values.sorted { $0.addedAt > $1.addedAt } }
    public func save(_ entry: DictionaryEntry) {
        if !values.contains(where: { $0.entry.id == entry.id }) { values.append(VocabularyCard(entry: entry.vocabularySnapshot)) }
    }
    public func remove(id: UUID) { values.removeAll { $0.id == id } }
    public func review(cardID: UUID, rating: ReviewRating, at date: Date) throws -> VocabularyCard {
        guard let index = values.firstIndex(where: { $0.id == cardID }) else { throw CocoaError(.fileNoSuchFile) }
        values[index].memory = FSRSScheduler().review(values[index].memory, rating: rating, at: date)
        return values[index]
    }
}

public struct MockOnlineDictionaryService: OnlineDictionaryService {
    public init() {}
    public func lookup(_ word: String) async -> DictionaryEntry? {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == SampleData.onlineEntry.headword.lowercased()
            ? SampleData.onlineEntry : nil
    }
}
