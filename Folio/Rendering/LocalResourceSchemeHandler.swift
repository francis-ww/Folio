import Foundation
import WebKit
import FolioCore

/// WebKit callbacks and task bookkeeping are confined to the main actor.
/// SQLite resource reads happen on the repository actor. Stopped tasks never receive callbacks.
@MainActor final class LocalResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let repository: any DictionaryRepository
    private let dictionaryID: String
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    var isDark = false
    var onFailure: @MainActor (FolioMessage) -> Void = { _ in }

    init(repository: any DictionaryRepository, dictionaryID: String) {
        self.repository = repository
        self.dictionaryID = dictionaryID
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        let dark = isDark
        tasks[id] = Task { @MainActor in
            defer { tasks[id] = nil }
            do {
                guard let url = urlSchemeTask.request.url, url.host == dictionaryID,
                      let original = try await repository.resource(path: url.path, dictionaryID: dictionaryID) else {
                    throw URLError(.fileDoesNotExist)
                }
                let mime = ResourcePath.mimeType(url.path)
                let data = await Task.detached(priority: .userInitiated) {
                    guard dark, mime == "text/css", let css = String(data: original, encoding: .utf8) ?? String(data: original, encoding: .utf16) else { return original }
                    return Data(DictionaryHTMLDocument.normalizeCSS(css, dark: true).utf8)
                }.value
                guard !Task.isCancelled, tasks[id] != nil else { return }
                let response = URLResponse(url: url, mimeType: mime,
                                           expectedContentLength: data.count, textEncodingName: dark && mime == "text/css" ? "utf-8" : nil)
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled, tasks[id] != nil else { return }
                if let archiveError = error as? any FolioMessageProviding { onFailure(archiveError.message) }
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
