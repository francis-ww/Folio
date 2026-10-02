import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class SearchViewModel {
    var query = ""
    private(set) var results: [DictionaryEntry] = []
    private(set) var isSearching = false
    private(set) var error: String?
    private var request = UUID()
    private let dictionary: any DictionaryRepository

    init(dictionary: any DictionaryRepository) { self.dictionary = dictionary }

    func search() async {
        let current = UUID()
        request = current
        isSearching = true
        error = nil
        let text = query
        do {
            if !text.isEmpty { try await Task.sleep(for: .milliseconds(220)) }
            let values = try await dictionary.search(text)
            try Task.checkCancellation()
            guard request == current else { return }
            results = values
            isSearching = false
        } catch is CancellationError {
            if request == current { isSearching = false }
        } catch {
            if request == current { self.error = error.localizedDescription; isSearching = false }
        }
    }
}
