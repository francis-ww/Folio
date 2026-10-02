import Foundation
import Observation
import SwiftData
import FolioCore

@MainActor @Observable
final class AppServices {
    let dictionary: any DictionaryRepository
    let vocabulary: any VocabularyRepository
    let library: DictionaryLibrary?
    let documentsScanner: DocumentsDictionaryScanner?
    let language: AppLanguageManager
    let appearance: AppAppearanceManager
    let dictionarySelection: any DictionarySelectionStore
    let onlineSettings: any OnlineDictionarySettingsStore
    var cards: [VocabularyCard] = []
    var error: FolioMessage?
    var libraryRevision = 0
    private(set) var isScanningDocuments = false
    private(set) var documentsStatus: FolioMessage?
    private(set) var documentsFailures: [FolioMessage] = []
    private var documentsTask: Task<Void, Never>?
    private var rescanRequested = false

    init(dictionary: any DictionaryRepository, vocabulary: any VocabularyRepository, library: DictionaryLibrary? = nil,
         onlineSettings: any OnlineDictionarySettingsStore = MemoryOnlineDictionarySettings(),
         language: AppLanguageManager? = nil, appearance: AppAppearanceManager? = nil,
         dictionarySelection: any DictionarySelectionStore = MemoryDictionarySelectionStore(),
         documentsScanner: DocumentsDictionaryScanner? = nil) {
        self.dictionary = dictionary
        self.vocabulary = vocabulary
        self.library = library
        self.documentsScanner = documentsScanner
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

    /// Startup stays fast: RootView starts this after the app hierarchy is visible.
    /// Lifecycle and manual requests share a queue; a request during indexing gets a final rescan.
    func scanDocuments() async {
        guard let documentsScanner else { return }
        if let documentsTask {
            rescanRequested = true
            await documentsTask.value
            return
        }
        isScanningDocuments = true
        documentsStatus = FolioMessage("Scanning your Documents folder…")
        documentsFailures = []
        let task = Task {
            defer { isScanningDocuments = false; documentsTask = nil }
            repeat {
                rescanRequested = false
                do {
                    let report = try await documentsScanner.scan()
                    documentsFailures = report.failures
                    if !report.failures.isEmpty { documentsStatus = FolioMessage("Scan complete. Some files need attention.") }
                    else {
                        documentsStatus = report.discoveredCount == 0
                            ? FolioMessage("No MDX dictionaries found in Folio’s folder.")
                            : FolioMessage("Your Documents folder is up to date.")
                    }
                    if report.hasChanges { libraryRevision += 1 }
                } catch {
                    documentsStatus = nil
                    documentsFailures = [.from(error, fallback: "Folio’s Documents folder couldn’t be scanned. Please try again.")]
                }
            } while rescanRequested
        }
        documentsTask = task
        await task.value
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
            guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw CocoaError(.fileNoSuchFile)
            }
            let scanner = try DocumentsDictionaryScanner(root: documents, library: dictionary)
            return (dictionary, vocabulary, scanner)
        }.value
        let settings = KeychainOnlineDictionarySettings()
        let online = YoudaoDictionaryService(settings: settings)
        let selection = UserDefaultsDictionarySelectionStore()
        let coordinator = DictionaryLookupCoordinator(local: bundle.0, online: online, selection: selection)
        let services = AppServices(dictionary: coordinator, vocabulary: bundle.1, library: bundle.0, onlineSettings: settings,
                                   language: language, appearance: appearance, dictionarySelection: selection, documentsScanner: bundle.2)
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
