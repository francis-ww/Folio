import SwiftUI
import FolioCore

struct RatingButton: View {
    let rating: ReviewRating
    let interval: TimeInterval
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(LocalizedStringKey(rating.title)).font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: AppLocalization.reviewInterval(interval, locale: locale))
                    .font(.caption.monospacedDigit()).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 6).frame(minWidth: 68, maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(rating == .good ? Theme.paper : Theme.ink)
                .background(rating == .good ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.rule, lineWidth: rating == .good ? 0 : 1) }
        }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: AppLocalization.string(
            FolioMessage("%@, next review in %@", [.message(FolioMessage(rating.title)),
                .text(AppLocalization.reviewInterval(interval, locale: locale))]), locale: locale)))
    }
}

#Preview { HStack { ForEach(ReviewRating.allCases, id: \.rawValue) { RatingButton(rating: $0, interval: 600) {} } }.padding().background(Theme.paper) }
#Preview("简体中文 · Large Text") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
        ForEach(ReviewRating.allCases, id: \.rawValue) { RatingButton(rating: $0, interval: 90) {} }
    }.environment(\.locale, Locale(identifier: "zh-Hans"))
        .environment(\.dynamicTypeSize, .accessibility3).frame(width: 280).padding().background(Theme.paper)
}
