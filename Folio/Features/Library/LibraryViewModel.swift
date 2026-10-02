import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class LibraryViewModel {
    private(set) var sources: [DictionarySource] = []
    private(set) var isImporting = false
    private(set) var status: String?
    var error: String?
    private var importTask: Task<Void, Never>?

    func refresh(_ services: AppServices) async {
        do { sources = try await services.dictionary.sources() }
        catch { self.error = error.localizedDescription }
    }

    func importFiles(_ urls: [URL], services: AppServices) {
        guard let library = services.library, !isImporting, !urls.isEmpty else { return }
        isImporting = true
        status = "Reading and indexing your dictionaries…"
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
                status = "Your dictionaries are ready."
                await refresh(services)
            } catch is CancellationError {
                status = "Import cancelled."
            } catch {
                self.error = error.localizedDescription
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
        } catch { self.error = error.localizedDescription }
    }
}
