import Foundation

/// Parses and decodes internal dictionary entry navigation links (e.g. `entry://`, `bphrase://`, `bword://`).
public enum DictionaryLinkParser: Sendable {
    /// Supported dictionary link schemes.
    public static let supportedSchemes: Set<String> = ["entry", "bphrase", "bword"]

    /// Returns true if the URL scheme matches a supported dictionary link scheme.
    public static func isEntryLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return supportedSchemes.contains(scheme)
    }

    /// Extracts and decodes the target headword or phrase from a dictionary link URL.
    /// Strips scheme prefix, slashes, query parameters, and URL fragments, then performs
    /// percent decoding and HTML entity decoding.
    public static func extractTarget(from url: URL) -> String {
        var raw = url.absoluteString
        if let colonIndex = raw.range(of: ":")?.upperBound {
            raw = String(raw[colonIndex...])
        }
        while raw.hasPrefix("/") {
            raw.removeFirst()
        }
        if let queryIndex = raw.firstIndex(of: "?") {
            raw = String(raw[..<queryIndex])
        }
        if let fragmentIndex = raw.firstIndex(of: "#") {
            raw = String(raw[..<fragmentIndex])
        }
        let percentDecoded = raw.removingPercentEncoding ?? raw
        let entityDecoded = percentDecoded.decodingHTMLEntities
        var cleaned = entityDecoded.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
