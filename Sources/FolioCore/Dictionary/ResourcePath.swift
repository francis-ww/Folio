import Foundation

public enum ResourcePath {
    /// Keys are database lookups, never filesystem paths.
    public static func normalize(_ raw: String) -> String? {
        let decoded = (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "\\", with: "/")
        let components = decoded.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.isEmpty, !components.contains(".."), !decoded.contains("\0"),
              !decoded.contains(":") else { return nil }
        return "/" + components.filter { $0 != "." }.joined(separator: "/").lowercased()
    }

    public static func mimeType(_ path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "svg": "image/svg+xml"
        case "webp": "image/webp"
        case "wav": "audio/wav"
        case "mp3": "audio/mpeg"
        case "ogg": "audio/ogg"
        case "css": "text/css"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        case "ttf": "font/ttf"
        default: "application/octet-stream"
        }
    }
}
