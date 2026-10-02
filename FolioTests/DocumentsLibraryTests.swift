import Foundation
import SwiftUI
import Testing
import FolioCore
@testable import Folio

struct DocumentsLibraryTests {
    @Test @MainActor func scanStateRecoversAfterMissingDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Folio.LibraryTests.\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try DictionaryLibrary(path: ":memory:")
        let scanner = try DocumentsDictionaryScanner(root: root, library: library)
        let services = AppServices(dictionary: library, vocabulary: MockVocabularyRepository(cards: []), library: library,
            language: AppLanguageManager(defaults: nil), appearance: AppAppearanceManager(defaults: nil), documentsScanner: scanner)
        try FileManager.default.removeItem(at: root)
        await services.scanDocuments()
        #expect(!services.isScanningDocuments && services.documentsFailures.count == 1)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        await services.scanDocuments()
        #expect(!services.isScanningDocuments && services.documentsFailures.isEmpty)
        #expect(services.documentsStatus?.key == "No MDX dictionaries found in Folio’s folder.")
        #expect(services.libraryRevision == 0)
    }

    @Test @MainActor func filesGuideFitsNarrowScreensInBothLanguagesAndAppearances() throws {
        for language in ["en", "zh-Hans"] {
            for scheme in [ColorScheme.light, .dark] {
                let content = FilesDictionaryGuide().padding().frame(width: 320)
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility2)
                let controller = UIHostingController(rootView: content)
                let size = controller.sizeThatFits(in: CGSize(width: 320, height: .greatestFiniteMagnitude))
                #expect(size.width <= 320.5 && size.height.isFinite && size.height > 0)
                #expect(ImageRenderer(content: content).uiImage != nil)
            }
        }
    }
}
