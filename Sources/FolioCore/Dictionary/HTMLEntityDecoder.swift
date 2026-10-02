import Foundation

/// Fast HTML entity decoding and escaping for headwords, summaries, and text views.
public enum HTMLEntityDecoder: Sendable {
    private static let namedEntities: [String: Character] = [
        "amp": "&",
        "lt": "<",
        "gt": ">",
        "quot": "\"",
        "apos": "'",
        "nbsp": " ",
        "mdash": "—",
        "ndash": "–",
        "hellip": "…",
        "lsquo": "‘",
        "rsquo": "’",
        "ldquo": "“",
        "rdquo": "”",
        "bull": "•",
        "prime": "′",
        "cent": "¢",
        "pound": "£",
        "yen": "¥",
        "euro": "€",
        "copy": "©",
        "reg": "®",
        "deg": "°",
        "plusmn": "±",
        "times": "×",
        "divide": "÷",
        "aacute": "á", "eacute": "é", "iacute": "í", "oacute": "ó", "uacute": "ú",
        "Aacute": "Á", "Eacute": "É", "Iacute": "Í", "Oacute": "Ó", "Uacute": "Ú",
        "agrave": "à", "egrave": "è", "igrave": "ì", "ograve": "ò", "ugrave": "ù",
        "Agrave": "À", "Egrave": "È", "Igrave": "Ì", "Ograve": "Ò", "Ugrave": "Ù",
        "acirc": "â", "ecirc": "ê", "icirc": "î", "ocirc": "ô", "ucirc": "û",
        "Acirc": "Â", "Ecirc": "Ê", "Icirc": "Î", "Ocirc": "Ô", "Ucirc": "Û",
        "auml": "ä", "euml": "ë", "iuml": "ï", "ouml": "ö", "uuml": "ü",
        "Auml": "Ä", "Euml": "Ë", "Iuml": "Ï", "Ouml": "Ö", "Uuml": "Ü",
        "atilde": "ã", "ntilde": "ñ", "otilde": "õ",
        "Atilde": "Ã", "Ntilde": "Ñ", "Otilde": "Õ",
        "ccedil": "ç", "Ccedil": "Ç",
        "aring": "å", "Aring": "Å",
        "aelig": "æ", "AElig": "Æ",
        "oelig": "œ", "OElig": "Œ"
    ]

    /// Unescapes HTML entities in a given string.
    /// Fast path returns immediately if the string contains no ampersand.
    public static func decode(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        result.reserveCapacity(string.count)
        var index = string.startIndex

        while index < string.endIndex {
            if string[index] == "&" {
                var search = string.index(after: index)
                var count = 0
                var foundSemicolon = false
                while search < string.endIndex && count < 10 {
                    let char = string[search]
                    if char == ";" {
                        foundSemicolon = true
                        break
                    }
                    if char == "&" || char.isWhitespace {
                        break
                    }
                    search = string.index(after: search)
                    count += 1
                }

                if foundSemicolon {
                    let entityName = String(string[string.index(after: index)..<search])
                    if let char = decodeEntity(entityName) {
                        result.append(char)
                        index = string.index(after: search)
                        continue
                    }
                }
            }

            result.append(string[index])
            index = string.index(after: index)
        }

        return result
    }

    /// Escapes common characters that dictionaries may have encoded as HTML entities.
    public static func escape(_ string: String) -> String {
        guard string.contains(where: { $0 == "&" || $0 == "<" || $0 == ">" || $0 == "\"" || $0 == "'" }) else {
            return string
        }
        var result = ""
        result.reserveCapacity(string.count + 8)
        for char in string {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            case "\"": result.append("&quot;")
            case "'": result.append("&#39;")
            default: result.append(char)
            }
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> Character? {
        if let char = namedEntities[name] {
            return char
        }
        if name.hasPrefix("#") {
            let numStr = name.dropFirst()
            if numStr.hasPrefix("x") || numStr.hasPrefix("X") {
                let hexStr = numStr.dropFirst()
                guard let code = UInt32(hexStr, radix: 16),
                      let scalar = UnicodeScalar(code) else { return nil }
                return Character(scalar)
            } else {
                guard let code = UInt32(numStr, radix: 10),
                      let scalar = UnicodeScalar(code) else { return nil }
                return Character(scalar)
            }
        }
        return nil
    }
}

public extension String {
    /// Returns the string with HTML entities unescaped.
    var decodingHTMLEntities: String {
        HTMLEntityDecoder.decode(self)
    }
}
