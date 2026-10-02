import Foundation
import Observation
import SwiftData
import FolioCore

@MainActor @Observable
final class AppServices {
    let dictionary: any DictionaryRepository
    let vocabulary: any VocabularyRepository
    let library: DictionaryLibrary?
    var cards: [VocabularyCard] = []
    var error: String?
    var libraryRevision = 0

    init(dictionary: any DictionaryRepository, vocabulary: any VocabularyRepository, library: DictionaryLibrary? = nil) {
        self.dictionary = dictionary
        self.vocabulary = vocabulary
        self.library = library
    }

    var dueCount: Int { cards.filter { $0.memory.due <= .now }.count }
    func isSaved(_ entry: DictionaryEntry) -> Bool { cards.contains { $0.entry.id == entry.id } }

    func refreshCards() async {
        do { cards = try await vocabulary.cards() }
        catch { self.error = error.localizedDescription }
    }

    static func makeLive() async throws -> AppServices {
        let bundle = try await Task.detached(priority: .userInitiated) {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true).appendingPathComponent("Folio", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: directory.appendingPathComponent("Vocabulary.store"))
            let container = try ModelContainer(for: StoredWord.self, StoredReview.self, configurations: configuration)
            let vocabulary = SwiftDataVocabularyRepository(modelContainer: container)
            let dictionary = try DictionaryLibrary(path: directory.appendingPathComponent("Dictionary.sqlite").path)
            try await dictionary.seedSamples()
            return (dictionary, vocabulary)
        }.value
        let services = AppServices(dictionary: bundle.0, vocabulary: bundle.1, library: bundle.0)
        await services.refreshCards()
        return services
    }

    static func preview() -> AppServices {
        let values = SampleData.cards()
        let services = AppServices(dictionary: MockDictionaryRepository(), vocabulary: MockVocabularyRepository(cards: values))
        services.cards = values
        return services
    }
}
