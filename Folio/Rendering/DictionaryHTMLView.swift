import SwiftUI
import WebKit
import AVFoundation
import FolioCore

struct DictionaryHTMLView: UIViewRepresentable {
    let entry: DictionaryEntry
    let repository: any DictionaryRepository
    var onLookup: @MainActor (String) -> Void = { _ in }
    var onNavigateToEntry: (@MainActor (String) -> Void)? = nil
    var onResourceFailure: @MainActor (FolioMessage) -> Void = { _ in }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var fontSize = 17.0

    private static let collapsibleUserScript: WKUserScript = {
        let source = #"""
        (function() {
            try {
                var style = document.createElement('style');
                style.setAttribute('data-folio-collapsible', 'true');
                style.textContent = '.unbox, .collapse, .collapsible, [data-toggle="collapse"], div[id^="origin_"], .box_title, .unbox_head, [class*="collapse"], [class*="collaps"] { cursor: pointer; }';
                document.head.appendChild(style);
            } catch (e) {}

            function toggleElement(el, forceState) {
                if (!el) return false;
                var style = window.getComputedStyle(el);
                var isHidden = style.display === 'none' ||
                    el.classList.contains('hidden') ||
                    el.classList.contains('collapsed') ||
                    el.classList.contains('hide') ||
                    el.getAttribute('aria-hidden') === 'true' ||
                    el.style.display === 'none';

                var shouldOpen = forceState !== undefined ? forceState : isHidden;

                if (shouldOpen) {
                    el.style.setProperty('display', 'block', 'important');
                    el.classList.remove('hidden', 'collapsed', 'hide');
                    el.classList.add('active', 'open', 'expanded', 'show');
                    el.setAttribute('aria-hidden', 'false');
                } else {
                    el.style.setProperty('display', 'none', 'important');
                    el.classList.remove('active', 'open', 'expanded', 'show');
                    el.classList.add('hidden', 'collapsed', 'hide');
                    el.setAttribute('aria-hidden', 'true');
                }
                return shouldOpen;
            }

            window.unbox = window.unbox || function(id) {
                var el = document.getElementById(id) || document.getElementById('unbox_' + id);
                if (el) toggleElement(el);
            };
            window.toggle = window.toggle || function(id) {
                var el = document.getElementById(id);
                if (el) toggleElement(el);
            };
            window.collapse = window.collapse || function(id) {
                var el = document.getElementById(id);
                if (el) toggleElement(el);
            };
            window.showHide = window.showHide || function(id) {
                var el = document.getElementById(id);
                if (el) toggleElement(el);
            };

            function flipIcon(trigger, isOpen) {
                if (!trigger) return;
                if (isOpen) {
                    trigger.classList.add('active', 'open', 'expanded');
                    trigger.classList.remove('collapsed');
                    trigger.setAttribute('aria-expanded', 'true');
                } else {
                    trigger.classList.remove('active', 'open', 'expanded');
                    trigger.classList.add('collapsed');
                    trigger.setAttribute('aria-expanded', 'false');
                }

                var icon = trigger.querySelector('.icon, .sign, .symbol, .plus, .minus, .plus-minus, .expander, .arrow, [class*="icon"], [class*="toggle"]');
                if (icon && icon !== trigger) {
                    flipText(icon, isOpen);
                    return;
                }
                flipText(trigger, isOpen);
            }

            function flipText(el, isOpen) {
                var walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT, null, false);
                var node;
                while ((node = walker.nextNode())) {
                    var val = node.nodeValue;
                    if (/[+\-−＋－▸▾▶▼]/.test(val)) {
                        if (isOpen) {
                            node.nodeValue = val
                                .replace(/\+/, '-')
                                .replace(/＋/, '－')
                                .replace(/▸/, '▾')
                                .replace(/▶/, '▼');
                        } else {
                            node.nodeValue = val
                                .replace(/[-−]/, '+')
                                .replace(/－/, '＋')
                                .replace(/▾/, '▸')
                                .replace(/▼/, '▶');
                        }
                        return;
                    }
                }
            }

            document.addEventListener('click', function(e) {
                var link = e.target.closest('a');
                if (link) {
                    var href = (link.getAttribute('href') || '').toLowerCase();
                    if (href.startsWith('entry:') || href.startsWith('bphrase:') || href.startsWith('bword:') || href.startsWith('sound:') || href.startsWith('folio-resource:')) {
                        return;
                    }
                }

                var trigger = null;
                var curr = e.target;
                while (curr && curr !== document.body && curr !== document.documentElement) {
                    var id = (curr.id || '').toLowerCase();
                    var cls = (typeof curr.className === 'string' ? curr.className : '').toLowerCase();
                    var text = (curr.textContent || '').trim();

                    var isCollapsibleClass = /\b(unbox|collapse|collapsible|toggle|expander|box_title|unbox_head|sec-title|head|header|title)\b/.test(cls);
                    var isCollapsibleId = /(_h|_head|_header|_title|_btn)$/.test(id) || /^(unbox_|toggle_|btn_)/.test(id) || /^origin_\d+_h$/.test(id);
                    var hasDataToggle = curr.hasAttribute('data-toggle') || curr.hasAttribute('data-target') || curr.hasAttribute('aria-expanded');
                    var hasOnClick = curr.hasAttribute('onclick') && /(toggle|unbox|collapse|showhide)/i.test(curr.getAttribute('onclick'));
                    var startsWithPlusMinus = /^[+\-−＋－▸▾▶▼]/.test(text);
                    var containsKeywords = /\b(word\s+origin|origin|extra\s+examples?|more\s+examples?|collocations?|synonyms?|thesaurus|etymology)\b/i.test(text);

                    if (isCollapsibleClass || isCollapsibleId || hasDataToggle || hasOnClick || startsWithPlusMinus || containsKeywords) {
                        trigger = curr;
                        break;
                    }
                    curr = curr.parentElement;
                }

                if (!trigger) return;

                var content = null;

                var targetSel = trigger.getAttribute('data-target') || trigger.getAttribute('data-bs-target');
                if (targetSel) {
                    try { content = document.querySelector(targetSel); } catch (err) {}
                }

                if (!content && trigger.tagName === 'A') {
                    var aHref = trigger.getAttribute('href') || '';
                    if (aHref.startsWith('#') && aHref.length > 1) {
                        content = document.getElementById(aHref.substring(1));
                    }
                }

                if (!content && trigger.hasAttribute('onclick')) {
                    var match = trigger.getAttribute('onclick').match(/(?:toggle|unbox|collapse|showhide)\s*\(\s*['"]([^'"]+)['"]/i);
                    if (match && match[1]) {
                        content = document.getElementById(match[1]) || document.getElementById('unbox_' + match[1]);
                    }
                }

                if (!content && trigger.id) {
                    var tid = trigger.id;
                    var stripped = tid.replace(/(_h|_head|_header|_title|_btn)$/i, '');
                    if (stripped !== tid) {
                        content = document.getElementById(stripped) || document.getElementById(stripped + '_body') || document.getElementById(stripped + '_content');
                    }
                    if (!content && tid.startsWith('unbox_')) {
                        var base = tid.substring(6);
                        content = document.getElementById(base) || document.getElementById(tid + '_body') || document.getElementById(tid + '_content');
                    }
                }

                if (!content && trigger.nextElementSibling) {
                    content = trigger.nextElementSibling;
                }

                if (!content && trigger.parentElement) {
                    var parent = trigger.parentElement;
                    content = parent.querySelector('.body, .content, .unbox_body, .box_content, .collapse, .collapsible, div[id^="origin_"], div[id*="origin"], div[id*="body"], div[id*="content"]');
                    if (content === trigger) content = null;
                }

                if (!content) {
                    content = trigger.querySelector('.body, .content, .unbox_body, .box_content, div[id^="origin_"], div[id*="body"]');
                }

                if (content && content !== trigger && !content.contains(trigger)) {
                    var triggerText = (trigger.textContent || '').trim();
                    var forceState = undefined;
                    if (/^[+＋▸▶]/.test(triggerText) || trigger.classList.contains('collapsed')) {
                        forceState = true;
                    } else if (/^[-−－▾▼]/.test(triggerText) || trigger.classList.contains('expanded') || trigger.classList.contains('open')) {
                        forceState = false;
                    }

                    var isOpen = toggleElement(content, forceState);
                    flipIcon(trigger, isOpen);
                    e.preventDefault();
                    e.stopPropagation();
                }
            }, false);
        })();
        """#
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }()

    static func extractTargetEntry(from url: URL) -> String {
        DictionaryLinkParser.extractTarget(from: url)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            repository: repository,
            dictionaryID: entry.dictionaryID,
            onLookup: onLookup,
            onNavigateToEntry: onNavigateToEntry,
            onResourceFailure: onResourceFailure
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptEnabled = true
        configuration.userContentController.addUserScript(Self.collapsibleUserScript)
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
        context.coordinator.onLookup = onLookup
        context.coordinator.onNavigateToEntry = onNavigateToEntry
        context.coordinator.onResourceFailure = onResourceFailure
        context.coordinator.resources.onFailure = onResourceFailure
        webView.accessibilityLabel = AppLocalization.string(FolioMessage("Dictionary definition"), locale: locale)
        if context.coordinator.audioFailed {
            webView.accessibilityHint = AppLocalization.string(FolioMessage("This pronunciation could not be played."), locale: locale)
        }
        let key = "\(entry.id):\(typeSize):\(colorScheme):\(fontSize)"
        guard context.coordinator.loadedKey != key else { return }
        context.coordinator.loadedKey = key
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
        var onNavigateToEntry: (@MainActor (String) -> Void)?
        var onResourceFailure: @MainActor (FolioMessage) -> Void
        var loadedKey: String?
        var audioTask: Task<Void, Never>?
        var renderTask: Task<Void, Never>?
        var player: AVAudioPlayer?
        var locale = Locale(identifier: "en")
        var audioFailed = false

        init(repository: any DictionaryRepository, dictionaryID: String, onLookup: @escaping @MainActor (String) -> Void,
             onNavigateToEntry: (@MainActor (String) -> Void)? = nil,
             onResourceFailure: @escaping @MainActor (FolioMessage) -> Void) {
            self.repository = repository
            self.dictionaryID = dictionaryID
            self.onLookup = onLookup
            self.onNavigateToEntry = onNavigateToEntry
            self.onResourceFailure = onResourceFailure
            resources = LocalResourceSchemeHandler(repository: repository, dictionaryID: dictionaryID)
            super.init()
            resources.onFailure = onResourceFailure
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
            if DictionaryLinkParser.isEntryLink(url) {
                decisionHandler(.cancel)
                let target = DictionaryLinkParser.extractTarget(from: url)
                if !target.isEmpty {
                    if let onNavigateToEntry {
                        onNavigateToEntry(target)
                    } else {
                        onLookup(target)
                    }
                }
                return
            }
            decisionHandler(.cancel)
            guard action.navigationType == .linkActivated else { return }
            if url.scheme == "folio-resource", url.host == dictionaryID {
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
                        guard !Task.isCancelled else { return }
                        if let archiveError = error as? any FolioMessageProviding { onResourceFailure(archiveError.message) }
                        audioFailed = true
                        webView.accessibilityHint = AppLocalization.string(FolioMessage("This pronunciation could not be played."), locale: locale)
                    }
                }
            }
        }
    }
}

#Preview { DictionaryHTMLView(entry: .init(id: "preview", headword: "folio", summary: "A page of a book.", html: "<p><i>noun</i></p><p>A page of a book.</p>"), repository: MockDictionaryRepository(), onLookup: { _ in }).padding().background(Theme.paper) }
