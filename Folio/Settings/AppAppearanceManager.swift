import SwiftUI
import Observation

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

@MainActor @Observable
final class AppAppearanceManager {
    static let preferenceKey = "app_appearance"
    @ObservationIgnored private let defaults: UserDefaults?
    var selection: AppAppearance {
        didSet { defaults?.set(selection.rawValue, forKey: Self.preferenceKey) }
    }
    init(defaults: UserDefaults? = .standard, initial: AppAppearance = .system) {
        self.defaults = defaults
        selection = defaults?.string(forKey: Self.preferenceKey).flatMap(AppAppearance.init(rawValue:)) ?? initial
    }
}
