import Foundation
import FolioCore

enum AppLocalization {
    /// Locale controls formatting in Foundation; selecting the lproj bundle also
    /// selects the translation, independently of the device's preferred language.
    static func bundle(for locale: Locale, in bundle: Bundle = .main) -> Bundle {
        let language = locale.identifier.hasPrefix("zh") ? "zh-Hans" : "en"
        guard let path = bundle.path(forResource: language, ofType: "lproj"), let localized = Bundle(path: path) else { return bundle }
        return localized
    }

    static func string(_ message: FolioMessage, locale: Locale, bundle: Bundle = .main) -> String {
        let format = self.bundle(for: locale, in: bundle).localizedString(forKey: message.key, value: message.key, table: "Localizable")
        let arguments: [CVarArg] = message.arguments.map {
            switch $0 {
            case .text(let value): value
            case .integer(let value): Int64(value)
            case .message(let value): string(value, locale: locale, bundle: bundle)
            }
        }
        return String(format: format, locale: locale, arguments: arguments)
    }

    static func reviewInterval(_ seconds: TimeInterval, locale: Locale) -> String {
        let divisor: Double = seconds < 3_600 ? 60 : (seconds < 86_400 ? 3_600 : 86_400)
        let key = seconds < 3_600 ? "%@ min" : (seconds < 86_400 ? "%@ h" : "%@ d")
        let value = (seconds / divisor).formatted(.number.precision(.fractionLength(0...1)).locale(locale))
        return string(FolioMessage(key, [.text(value)]), locale: locale)
    }
}
