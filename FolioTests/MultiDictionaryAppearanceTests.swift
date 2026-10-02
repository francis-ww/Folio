import Foundation
import SwiftUI
import Testing
import FolioCore
@testable import Folio

struct MultiDictionaryAppearanceTests {
    @Test @MainActor func appearancePersistsAndSystemRemovesOverride() throws {
        let suite = "Folio.AppearanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = AppAppearanceManager(defaults: defaults)
        #expect(manager.selection == .system && manager.selection.colorScheme == nil)
        for choice in AppAppearance.allCases {
            manager.selection = choice
            let reopened = AppAppearanceManager(defaults: defaults)
            #expect(reopened.selection == choice)
        }
        manager.selection = .dark
        #expect(manager.selection.colorScheme == .dark)
        manager.selection = .system
        #expect(manager.selection.colorScheme == nil)
    }

    @Test @MainActor func sourceSelectionUpdatesImmediatelyAndPersistsInOrder() async throws {
        let services = AppServices.preview()
        let model = LibraryViewModel()
        await model.refresh(services)
        model.setEnabled(false, id: "a", services: services)
        #expect(!model.selection.isEnabled("a"))
        model.setEnabled(false, id: "b", services: services)
        model.reorder(["b", "a"], services: services)
        model.reorder(["a", "b"], services: services)
        await model.refresh(services)
        let saved = try await services.dictionarySelection.configuration()
        #expect(saved.disabledIDs == ["a", "b"])
        #expect(saved.priority.prefix(2) == ["a", "b"])
    }

    @Test @MainActor func selectingResultChangesSavedDefinition() async throws {
        let repository = PreviewMultipleDictionary()
        let services = AppServices(dictionary: repository, vocabulary: MockVocabularyRepository(cards: []),
            language: AppLanguageManager(defaults: nil), appearance: AppAppearanceManager(defaults: nil))
        let model = WordDetailViewModel(entry: SampleData.entries[0])
        await model.resolve(using: repository)
        #expect(model.results.map(\.id) == ["one", "two"])
        #expect(model.selectedSourceID == "one")
        model.select("two")
        #expect(model.entry.dictionaryID == "two")
        await model.save(using: services)
        #expect(services.cards.first?.entry.dictionaryID == "two")
        #expect(model.requestedHeadword == SampleData.entries[0].headword)
    }

    @Test @MainActor func settingsAndSourceTabsFitBothAppearancesAndLanguages() throws {
        for scheme in [ColorScheme.light, .dark] {
            for language in ["en", "zh-Hans"] {
                let content = VStack(spacing: 18) {
                    AppearanceSettingsView(manager: AppAppearanceManager(defaults: nil))
                    DictionarySelectionView(sources: [.youdao], selection: .init(), onToggle: { _, _ in }, onMove: { _, _ in }, onRemove: { _ in })
                    DictionaryResultTabs(results: [.init(source: .youdao, entry: SampleData.onlineEntry)], selectedID: "youdao-online", onSelect: { _ in })
                }.padding().frame(width: 320).environment(\.locale, Locale(identifier: language))
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility2)
                    .background(Theme.paper)
                let controller = UIHostingController(rootView: content)
                let size = controller.sizeThatFits(in: CGSize(width: 320, height: .greatestFiniteMagnitude))
                #expect(size.width <= 320.5 && size.height.isFinite)
                #expect(ImageRenderer(content: content).uiImage != nil)
            }
        }
    }
}

private struct PreviewMultipleDictionary: DictionaryRepository {
    func sources() async -> [DictionarySource] { ["one", "two"].map { .init(id: $0, title: $0, filename: $0, entryCount: 1) } }
    func lookup(_ word: String, dictionaryID: String) async -> DictionaryEntry? {
        .init(id: dictionaryID + word, dictionaryID: dictionaryID, headword: word, summary: dictionaryID)
    }
    func search(_ query: String) async -> [DictionaryEntry] { [] }
    func entry(id: String) async -> DictionaryEntry? { nil }
    func resource(path: String, dictionaryID: String) async -> Data? { nil }
}
