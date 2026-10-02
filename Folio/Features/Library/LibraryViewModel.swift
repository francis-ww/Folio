import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class LibraryViewModel {
    private(set) var sources: [DictionarySource] = []
    private(set) var selection = DictionarySelection()
    private(set) var isImporting = false
    private(set) var status: FolioMessage?
    var error: FolioMessage?
    private var importTask: Task<Void, Never>?
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

    func importFiles(_ urls: [URL], services: AppServices) {
        guard let library = services.library, !isImporting, !urls.isEmpty else { return }
        isImporting = true
        status = FolioMessage("Reading and indexing your dictionaries…")
        error = nil
        importTask = Task {
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer {
                accessed.forEach { $0.stopAccessingSecurityScopedResource() }
                isImporting = false
                importTask = nil
            }
            do {
                try await library.importArchives(urls)
                services.libraryRevision += 1
                status = FolioMessage("Your dictionaries are ready.")
                await refresh(services)
            } catch is CancellationError {
                status = FolioMessage("Import cancelled.")
            } catch {
                self.error = FolioMessage.from(error, fallback: "Your library couldn’t be updated. Please try again.")
                status = nil
            }
        }
    }

    func cancelImport() { importTask?.cancel() }

    func remove(_ source: DictionarySource, services: AppServices) async {
        guard let library = services.library, !isImporting else { return }
        do {
            try await library.removeSource(id: source.id)
            services.libraryRevision += 1
            await refresh(services)
        } catch { self.error = FolioMessage.from(error, fallback: "Your library couldn’t be updated. Please try again.") }
    }
}
