import Foundation

/// Exact and version/punctuation-normalized matches win. Prefix matching requires a
/// meaningful shared name and a unique best candidate; ambiguous resources stay unpaired.
enum DictionaryFilePairing {
    static func match(resourceStem: String, dictionaryStems: [String], allowSingleFallback: Bool = true) -> String? {
        let names = Array(Set(dictionaryStems))
        if let exact = names.first(where: { $0.caseInsensitiveCompare(resourceStem) == .orderedSame }) { return exact }
        let resource = normalized(resourceStem)
        let matches = names.filter { normalized($0) == resource }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { return nil }
        let prefixMatches = names.filter {
            let name = normalized($0)
            return min(name.count, resource.count) >= 4 && (name.hasPrefix(resource) || resource.hasPrefix(name))
        }
        if prefixMatches.count == 1 { return prefixMatches[0] }
        // One dictionary and one resource in an explicitly selected set/directory is safe.
        return allowSingleFallback && names.count == 1 ? names[0] : nil
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: #"[\s_\-.()\[\]]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?:version|ver|v)(?=\d)"#, with: "", options: .regularExpression)
    }
}
