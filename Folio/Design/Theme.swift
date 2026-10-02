import SwiftUI

@MainActor enum Theme {
    static let paper = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.secondarySystemBackground
        : UIColor(red: 0.97, green: 0.96, blue: 0.94, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor.tertiarySystemBackground
        : UIColor(red: 0.99, green: 0.985, blue: 0.97, alpha: 1) })
    static let ink = Color.primary
    static let muted = Color.secondary
    static let error = Color(uiColor: .systemRed)
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.66, green: 0.76, blue: 0.62, alpha: 1)
        : UIColor(red: 0.32, green: 0.42, blue: 0.29, alpha: 1) })
    static let rule = Color.primary.opacity(0.12)
    static let display = Font.custom("Georgia", size: 44, relativeTo: .largeTitle)
    static let title = Font.custom("Georgia", size: 30, relativeTo: .title)
    static let headword = Font.custom("Georgia", size: 26, relativeTo: .title2)
    static let margin: CGFloat = 24
    static let motion = Animation.spring(response: 0.35, dampingFraction: 0.85)
}
