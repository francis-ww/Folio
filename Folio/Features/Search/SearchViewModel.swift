import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: [DictionaryEntry] = []
    private(set) var failures: [DictionarySourceFailure] = []
    private(set) var sources: [DictionarySource] = []
    private(set) var isSearching = false
    private(set) var error: FolioMessage?
    private var request = UUID()
    private let dictionary: any DictionaryRepository

    init(dictionary: any DictionaryRepository) { self.dictionary = dictionary }

    func search() async {
        let current = UUID()
        request = current
        isSearching = true
        error = nil
        results = []
        failures = []
        let text = query
        do {
            if !text.isEmpty { try await Task.sleep(for: .milliseconds(220)) }
            let report = try await dictionary.searchReport(text)
            try Task.checkCancellation()
            guard request == current else { return }
            results = report.entries
            failures = report.failures
            sources = report.sources
            isSearching = false
        } catch is CancellationError {
            if request == current { isSearching = false }
        } catch {
            if request == current { self.error = FolioMessage.from(error, fallback: "The dictionary couldn’t be searched. Please try again."); isSearching = false }
        }
    }
}
