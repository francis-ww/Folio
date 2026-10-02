import Foundation

/// Pure document preparation runs away from the main actor. Author layout,
/// typography, and background images remain intact; dark mode owns text/paint.
public enum DictionaryHTMLDocument {
    public static func make(html: String, baseURL: URL, dark: Bool, fontSize: Double) -> String {
        let content = html.replacingOccurrences(of: "sound://", with: baseURL.absoluteString, options: .caseInsensitive)
        let body = dark ? normalizeHTML(content) : content
        let size = fontSize.isFinite ? min(128, max(12, fontSize)) : 17
        let darkRules = """
            html, body {background: #1C1C1E !important; color: #E5E5EA !important}
            body :where(*:not(img):not(svg):not(path):not(video):not(audio)) {
                color: #E5E5EA !important; background-color: transparent !important;
                border-color: #48484A !important; text-shadow: none !important;
            }
            body a, body a * {color: #AAC19E !important}
            body mark {background-color: #3A3A3C !important}
            """
        return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src folio-resource: data:; style-src 'unsafe-inline' folio-resource:; font-src folio-resource: data:; media-src folio-resource:; script-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'">
            </head><body>\(body)
            <style>:root {color-scheme: \(dark ? "dark" : "light")}
            body {margin: 0; font: \(size)px/1.7 -apple-system, sans-serif; color: #252823; overflow-wrap: anywhere}
            img, video {max-width: 100%; height: auto} a {color: #526B49}
            table, audio {max-width: 100%}
            \(dark ? darkRules : "")
            </style></body></html>
            """
    }

    /// The declaration scanner protects quoted strings, comments, and URLs.
    /// Removing author paint declarations, including !important, lets host dark
    /// rules work with inline styles and MDD stylesheets alike.
    public static func normalizeCSS(_ css: String, dark: Bool) -> String {
        guard dark else { return css }
        let characters = Array(css)
        var output = "", start = 0, index = 0, parentheses = 0
        var quote: Character?, comment = false
        func declaration(_ range: Range<Int>) -> String {
            let original = String(characters[range])
            let value = original.replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            guard let colon = value.firstIndex(of: ":") else { return original }
            let property = value[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["color", "background-color", "background"].contains(property) else { return original }
            if property == "background", value.lowercased().contains("url(") {
                return original.replacingOccurrences(of: #"(?is)!\s*important\s*(?:/\*.*?\*/\s*)*$"#, with: "", options: .regularExpression)
            }
            return ""
        }
        while index < characters.count {
            let current = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if comment {
                if current == "*", next == "/" { comment = false; index += 2; continue }
            } else if let currentQuote = quote {
                if current == "\\" { index += 2; continue }
                if current == currentQuote { quote = nil }
            } else if current == "/", next == "*" {
                comment = true; index += 2; continue
            } else if current == "\"" || current == "'" { quote = current }
            else if current == "(" { parentheses += 1 }
            else if current == ")" { parentheses = max(0, parentheses - 1) }
            else if parentheses == 0 {
                if current == "{" { output += String(characters[start..<index]) + "{"; start = index + 1 }
                else if current == ";" || current == "}" { output += declaration(start..<index) + String(current); start = index + 1 }
            }
            index += 1
        }
        output += declaration(start..<characters.count)
        return output
    }

    private static func replacing(_ source: String, pattern: String, transform: (NSTextCheckingResult, NSString) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let text = source as NSString
        let result = NSMutableString(string: source)
        for match in expression.matches(in: source, range: NSRange(location: 0, length: text.length)).reversed() {
            result.replaceCharacters(in: match.range, with: transform(match, text))
        }
        return result as String
    }
    private static func normalizeHTML(_ html: String) -> String {
        let styles = replacing(html, pattern: #"(?is)(<style\b[^>]*>)(.*?)(</style\s*>)"#) { match, source in
            source.substring(with: match.range(at: 1)) + normalizeCSS(source.substring(with: match.range(at: 2)), dark: true)
                + source.substring(with: match.range(at: 3))
        }
        return replacing(styles, pattern: #"(?is)<[a-z][^>]*>"#) { match, source in
            replacing(source.substring(with: match.range), pattern: #"(?is)(\bstyle\s*=\s*)(["'])(.*?)\2"#) { attribute, tag in
                let quote = tag.substring(with: attribute.range(at: 2))
                return tag.substring(with: attribute.range(at: 1)) + quote
                    + normalizeCSS(tag.substring(with: attribute.range(at: 3)), dark: true) + quote
            }
        }
    }
}
