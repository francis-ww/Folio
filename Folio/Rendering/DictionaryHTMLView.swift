import SwiftUI
import WebKit
import AVFoundation
import FolioCore

struct DictionaryHTMLView: UIViewRepresentable {
    let entry: DictionaryEntry
    let repository: any DictionaryRepository
    let onLookup: @MainActor (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(repository: repository, dictionaryID: entry.dictionaryID, onLookup: onLookup) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.setURLSchemeHandler(context.coordinator.resources, forURLScheme: "folio-resource")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.accessibilityLabel = "Dictionary definition"
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let key = "\(entry.id):\(typeSize):\(colorScheme)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        context.coordinator.onLookup = onLookup
        let base = URL(string: "folio-resource://\(entry.dictionaryID)/")!
        let body = entry.html.replacingOccurrences(of: "sound://", with: base.absoluteString, options: .caseInsensitive)
        let dark = colorScheme == .dark
        let scale = UIFont.preferredFont(forTextStyle: .body).pointSize
        let document = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src folio-resource: data:; style-src 'unsafe-inline' folio-resource:; font-src folio-resource: data:; media-src folio-resource:; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
            <style>:root {color-scheme: \(dark ? "dark" : "light")}
            body {margin: 0; font: \(scale)px/1.7 -apple-system, sans-serif; color: \(dark ? "#eae8e0" : "#252823"); overflow-wrap: anywhere}
            img {max-width: 100%; height: auto} a {color: \(dark ? "#aac19e" : "#526b49")}
            table {max-width: 100%} audio {max-width: 100%}</style></head><body>\(body)</body></html>
            """
        webView.loadHTMLString(document, baseURL: base)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.resources.cancelAll()
        coordinator.audioTask?.cancel()
        coordinator.player?.stop()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let repository: any DictionaryRepository
        let dictionaryID: String
        let resources: LocalResourceSchemeHandler
        var onLookup: @MainActor (String) -> Void
        var loadedKey: String?
        var audioTask: Task<Void, Never>?
        var player: AVAudioPlayer?

        init(repository: any DictionaryRepository, dictionaryID: String, onLookup: @escaping @MainActor (String) -> Void) {
            self.repository = repository
            self.dictionaryID = dictionaryID
            self.onLookup = onLookup
            resources = LocalResourceSchemeHandler(repository: repository, dictionaryID: dictionaryID)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.navigationType == .other && (url.absoluteString == "about:blank" || url.scheme == "folio-resource") {
                decisionHandler(.allow)
                return
            }
            if action.navigationType == .linkActivated, url.scheme == "folio-resource",
               url.host == dictionaryID, url.path == "/", url.fragment != nil {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard action.navigationType == .linkActivated else { return }
            if ["entry", "bword"].contains(url.scheme?.lowercased() ?? "") {
                let word = String(url.absoluteString.dropFirst((url.scheme?.count ?? 0) + 3))
                onLookup(word.removingPercentEncoding ?? word)
            } else if url.scheme == "folio-resource", url.host == dictionaryID {
                guard ResourcePath.mimeType(url.path).hasPrefix("audio/") else { return }
                audioTask?.cancel()
                audioTask = Task {
                    do {
                        guard let data = try await repository.resource(path: url.path, dictionaryID: dictionaryID), !Task.isCancelled else { return }
                        player?.stop()
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                        try AVAudioSession.sharedInstance().setActive(true)
                        player = try AVAudioPlayer(data: data)
                        player?.play()
                    } catch { webView.accessibilityHint = "This pronunciation could not be played." }
                }
            }
        }
    }
}

#Preview { DictionaryHTMLView(entry: .init(id: "preview", headword: "folio", summary: "A page of a book.", html: "<p><i>noun</i></p><p>A page of a book.</p>"), repository: MockDictionaryRepository()) { _ in }.padding().background(Theme.paper) }
