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
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0

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
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.locale = locale
        webView.accessibilityLabel = AppLocalization.string(FolioMessage("Dictionary definition"), locale: locale)
        if context.coordinator.audioFailed {
            webView.accessibilityHint = AppLocalization.string(FolioMessage("This pronunciation could not be played."), locale: locale)
        }
        let key = "\(entry.id):\(typeSize):\(colorScheme):\(fontSize)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
        context.coordinator.onLookup = onLookup
        context.coordinator.renderTask?.cancel()
        context.coordinator.resources.cancelAll()
        context.coordinator.resources.isDark = colorScheme == .dark
        let base = URL(string: "folio-resource://\(entry.dictionaryID)/")!
        let html = entry.html, dark = colorScheme == .dark, size = fontSize
        let coordinator = context.coordinator
        coordinator.renderTask = Task { @MainActor in
            let document = await Task.detached(priority: .userInitiated) {
                DictionaryHTMLDocument.make(html: html, baseURL: base, dark: dark, fontSize: size)
            }.value
            guard !Task.isCancelled, coordinator.loadedKey == key else { return }
            webView.loadHTMLString(document, baseURL: base)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        coordinator.resources.cancelAll()
        coordinator.audioTask?.cancel()
        coordinator.renderTask?.cancel()
        coordinator.player?.stop()
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let repository: any DictionaryRepository
        let dictionaryID: String
        let resources: LocalResourceSchemeHandler
        var onLookup: @MainActor (String) -> Void
        var loadedKey: String?
        var audioTask: Task<Void, Never>?
        var renderTask: Task<Void, Never>?
        var player: AVAudioPlayer?
        var locale = Locale(identifier: "en")
        var audioFailed = false

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
                    audioFailed = false
                    webView.accessibilityHint = nil
                    do {
                        guard let data = try await repository.resource(path: url.path, dictionaryID: dictionaryID), !Task.isCancelled else { return }
                        player?.stop()
                        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                        try AVAudioSession.sharedInstance().setActive(true)
                        player = try AVAudioPlayer(data: data)
                        player?.play()
                    } catch {
                        audioFailed = true
                        webView.accessibilityHint = AppLocalization.string(FolioMessage("This pronunciation could not be played."), locale: locale)
                    }
                }
            }
        }
    }
}

#Preview { DictionaryHTMLView(entry: .init(id: "preview", headword: "folio", summary: "A page of a book.", html: "<p><i>noun</i></p><p>A page of a book.</p>"), repository: MockDictionaryRepository()) { _ in }.padding().background(Theme.paper) }
