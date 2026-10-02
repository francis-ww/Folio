import Foundation
import WebKit
import FolioCore

/// WebKit callbacks and task bookkeeping are confined to the main actor.
/// SQLite resource reads happen on the repository actor. Stopped tasks never receive callbacks.
@MainActor final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let repository: any DictionaryRepository
    private let dictionaryID: String
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(repository: any DictionaryRepository, dictionaryID: String) {
        self.repository = repository
        self.dictionaryID = dictionaryID
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id] = Task { @MainActor in
            defer { tasks[id] = nil }
            do {
                guard let url = urlSchemeTask.request.url, url.host == dictionaryID,
                      let data = try await repository.resource(path: url.path, dictionaryID: dictionaryID) else {
                    throw URLError(.fileDoesNotExist)
                }
                guard !Task.isCancelled, tasks[id] != nil else { return }
                let response = URLResponse(url: url, mimeType: ResourcePath.mimeType(url.path),
                                           expectedContentLength: data.count, textEncodingName: nil)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, tasks[id] != nil else { return }
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        tasks.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
