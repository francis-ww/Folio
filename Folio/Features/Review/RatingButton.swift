import SwiftUI
import FolioCore

struct RatingButton: View {
    let rating: ReviewRating
    let interval: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(rating.title).font(.subheadline.weight(.medium))
                Text(interval).font(.caption.monospacedDigit()).opacity(0.7)
            }.frame(maxWidth: .infinity).padding(.vertical, 16)
                .foregroundStyle(rating == .good ? Theme.paper : Theme.ink)
                .background(rating == .good ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(Theme.rule, lineWidth: rating == .good ? 0 : 1) }
        }.buttonStyle(.plain).accessibilityLabel("\(rating.title), next review in \(interval)")
    }
}

#Preview { HStack { ForEach(ReviewRating.allCases, id: \.rawValue) { RatingButton(rating: $0, interval: "10m") {} } }.padding().background(Theme.paper) }
