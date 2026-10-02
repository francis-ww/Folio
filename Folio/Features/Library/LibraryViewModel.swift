import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class LibraryViewModel {
    private(set) var sources: [DictionarySource] = []
    private(set) var selection = DictionarySelection()
    var error: FolioMessage?
    private var preferenceTask: Task<Void, Never>?
    private var preferenceRequest = UUID()

    func refresh(_ services: AppServices) async {
        await preferenceTask?.value
        do {
            selection = try await services.dictionarySelection.configuration()
            sources = selection.ordered(try await services.dictionary.sources())
        }
        catch { self.error = FolioMessage.from(error, fallback: "Your library couldn’t be updated. Please try again.") }
    }

    func setEnabled(_ enabled: Bool, id: String, services: AppServices) {
        selection.setEnabled(enabled, id: id)
        persist(services) { try await $0.setEnabled(enabled, id: id) }
    }

    func reorder(_ ids: [String], services: AppServices) {
        selection.reorder(ids)
        sources = selection.ordered(sources)
        persist(services) { try await $0.reorder(ids) }
    }

    private func persist(_ services: AppServices, operation: @escaping @Sendable (any DictionarySelectionStore) async throws -> Void) {
        let previous = preferenceTask
        let request = UUID()
        preferenceRequest = request
        preferenceTask = Task {
            await previous?.value
            do {
                try await operation(services.dictionarySelection)
                services.libraryRevision += 1
            } catch {
                self.error = .from(error, fallback: "Your library couldn’t be updated. Please try again.")
                if preferenceRequest == request, let stored = try? await services.dictionarySelection.configuration() {
                    selection = stored
                    sources = stored.ordered(sources)
                }
            }
        }
    }

    func remove(_ source: DictionarySource, services: AppServices) async {
        guard let library = services.library, !services.isScanningDocuments else { return }
        do {
            if let scanner = services.documentsScanner { try await scanner.removeDictionary(id: source.id) }
            else { try await library.removeSource(id: source.id) }
            services.libraryRevision += 1
            await refresh(services)
        } catch { self.error = FolioMessage.from(error, fallback: "Your library couldn’t be updated. Please try again.") }
    }
}
