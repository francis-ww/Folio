import Foundation
import Observation
import SwiftData
import FolioCore

@MainActor @Observable
final class AppServices {
    let dictionary: any DictionaryRepository
    let vocabulary: any VocabularyRepository
    let library: DictionaryLibrary?
    let language: AppLanguageManager
    let appearance: AppAppearanceManager
    let dictionarySelection: any DictionarySelectionStore
    let onlineSettings: any OnlineDictionarySettingsStore
    var cards: [VocabularyCard] = []
    var error: FolioMessage?
    var libraryRevision = 0

    init(dictionary: any DictionaryRepository, vocabulary: any VocabularyRepository, library: DictionaryLibrary? = nil,
         onlineSettings: any OnlineDictionarySettingsStore = MemoryOnlineDictionarySettings(),
         language: AppLanguageManager? = nil, appearance: AppAppearanceManager? = nil,
         dictionarySelection: any DictionarySelectionStore = MemoryDictionarySelectionStore()) {
        self.dictionary = dictionary
        self.vocabulary = vocabulary
        self.library = library
        self.onlineSettings = onlineSettings
        self.language = language ?? AppLanguageManager()
        self.appearance = appearance ?? AppAppearanceManager()
        self.dictionarySelection = dictionarySelection
    }

    var dueCount: Int { cards.filter { $0.memory.due <= .now }.count }
    func isSaved(_ entry: DictionaryEntry) -> Bool { cards.contains { $0.entry.id == entry.id } }

    func refreshCards() async {
        do { cards = try await vocabulary.cards() }
        catch { self.error = FolioMessage.from(error, fallback: "Your saved words couldn’t be loaded. Please try again.") }
    }

    static func makeLive(language: AppLanguageManager, appearance: AppAppearanceManager) async throws -> AppServices {
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
        let settings = KeychainOnlineDictionarySettings()
        let online = YoudaoDictionaryService(settings: settings)
        let selection = UserDefaultsDictionarySelectionStore()
        let coordinator = DictionaryLookupCoordinator(local: bundle.0, online: online, selection: selection)
        let services = AppServices(dictionary: coordinator, vocabulary: bundle.1, library: bundle.0, onlineSettings: settings,
                                   language: language, appearance: appearance, dictionarySelection: selection)
        await services.refreshCards()
        return services
    }

    static func preview(language: AppLanguage = .english) -> AppServices {
        let values = SampleData.cards()
        let selection = MemoryDictionarySelectionStore()
        let dictionary = DictionaryLookupCoordinator(local: MockDictionaryRepository(), online: MockOnlineDictionaryService(), selection: selection)
        let services = AppServices(dictionary: dictionary, vocabulary: MockVocabularyRepository(cards: values),
                                   language: AppLanguageManager(defaults: nil, initial: language), appearance: AppAppearanceManager(defaults: nil),
                                   dictionarySelection: selection)
        services.cards = values
        return services
    }
}
