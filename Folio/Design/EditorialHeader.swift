import SwiftUI

struct EditorialHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased()).font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
            Text(title).font(Theme.display).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 16).padding(.bottom, 12)
    }
}

#Preview { EditorialHeader(eyebrow: "A little, every day", title: "Your practice.", subtitle: "Make room for a few good words.").padding().background(Theme.paper) }
