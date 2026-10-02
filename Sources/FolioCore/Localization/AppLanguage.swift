import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Hashable, Sendable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var title: String {
        switch self {
        case .system: "System Default"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    public func resolvedIdentifier(preferredLanguages: [String] = Locale.preferredLanguages) -> String {
        guard self == .system else { return rawValue }
        for identifier in preferredLanguages {
            let language = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
            if language == "en" || language.hasPrefix("en-") { return "en" }
            if language == "zh" || language == "zh-hans" || language.hasPrefix("zh-hans-")
                || language == "zh-cn" || language == "zh-sg" { return "zh-Hans" }
        }
        return "en"
    }
}
