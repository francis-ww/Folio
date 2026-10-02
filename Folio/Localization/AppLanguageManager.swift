import Foundation
import Observation
import FolioCore

@MainActor @Observable
final class AppLanguageManager {
    static let preferenceKey = "app_language"
    @ObservationIgnored private let defaults: UserDefaults?
    private var systemLanguages: [String]

    var selection: AppLanguage {
        didSet { defaults?.set(selection.rawValue, forKey: Self.preferenceKey) }
    }

    init(defaults: UserDefaults? = .standard, initial: AppLanguage = .system,
         preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        self.selection = defaults?.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? initial
        self.systemLanguages = preferredLanguages
    }

    var currentLocale: Locale { Locale(identifier: selection.resolvedIdentifier(preferredLanguages: systemLanguages)) }

    func refreshSystemLocale() { systemLanguages = Locale.preferredLanguages }
}
