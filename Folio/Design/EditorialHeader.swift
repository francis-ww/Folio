import SwiftUI

struct EditorialHeader: View {
    let eyebrow: LocalizedStringKey
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow).textCase(.uppercase).font(.caption2.weight(.semibold)).tracking(locale.identifier.hasPrefix("zh") ? 0.5 : 2).foregroundStyle(Theme.muted)
            Text(title).font(locale.identifier.hasPrefix("zh") ? .system(.largeTitle, design: .serif) : Theme.display)
                .fixedSize(horizontal: false, vertical: true).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Text(subtitle).fixedSize(horizontal: false, vertical: true).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16).padding(.bottom, 12)
    }
}

#Preview { EditorialHeader(eyebrow: "A little, every day", title: "Make it\nyours.", subtitle: "A quiet moment for the words you keep.").padding().background(Theme.paper) }
