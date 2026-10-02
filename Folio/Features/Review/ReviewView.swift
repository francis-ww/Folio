import SwiftUI
import FolioCore

struct ReviewView: View {
    let services: AppServices
    @State private var model: ReviewViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: ReviewViewModel(vocabulary: services.vocabulary))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                EditorialHeader(eyebrow: "A little, every day", title: "Make it\nyours.", subtitle: "A quiet moment for the words you keep.")
                if let card = model.current {
                    HStack {
                        Text("\(model.completed + 1) OF \(model.total)").font(.caption2.weight(.semibold)).tracking(1.6)
                        Spacer()
                        Text("RECALL, THEN REVEAL").font(.caption2).tracking(1)
                    }.foregroundStyle(Theme.muted)
                    ProgressView(value: model.progress).tint(Theme.accent).accessibilityLabel("Session progress")
                    ReviewCardView(card: card, isRevealed: model.isRevealed)
                        .id(card.id).transition(.opacity)
                    if model.isRevealed {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { ratingButtons }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) { ratingButtons }
                        }
                        Text("Choose how easily the meaning came back.").font(.caption).foregroundStyle(Theme.muted)
                    } else {
                        Button("Reveal meaning") { model.reveal() }.buttonStyle(PrimaryButtonStyle())
                    }
                } else if model.completed > 0 {
                    ReviewCompletionView(count: model.completed)
                    Button("Check for more words") { Task { await model.begin(); await services.refreshCards() } }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    ContentUnavailableView {
                        Label("Room to breathe.", systemImage: "leaf")
                    } description: {
                        Text(services.cards.isEmpty ? "Save a word in Discover to begin your collection." : "You’re all caught up. Your next words will appear when they’re due.")
                    }
                    if let next = services.cards.map(\.memory.due).filter({ $0 > .now }).min() {
                        Text("Next review \(next, style: .relative) from now").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Button("Check for due words") { Task { await model.begin(); await services.refreshCards() } }
                        .buttonStyle(PrimaryButtonStyle())
                }
                if let error = model.error {
                    Text(error).font(.subheadline).foregroundStyle(.red)
                    Button("Restart session") { Task { await model.begin(); await services.refreshCards() } }
                        .disabled(model.isSaving)
                }
                Text("Short practice. Lasting memory.").font(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(.top, 10)
            }.padding(.horizontal, Theme.margin).padding(.bottom, 30)
        }
        .background(Theme.paper).toolbar(.hidden, for: .navigationBar)
        .task { if !model.hasStarted || model.current == nil { await model.begin() }; await services.refreshCards() }
        .sensoryFeedback(.selection, trigger: model.isRevealed)
        .sensoryFeedback(.success, trigger: model.completed)
        .animation(reduceMotion ? nil : Theme.motion, value: model.isRevealed)
        .animation(reduceMotion ? nil : Theme.motion, value: model.current?.id)
    }

    @ViewBuilder private var ratingButtons: some View {
        ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
            RatingButton(rating: rating, interval: model.interval(for: rating)) {
                Task { await model.rate(rating); await services.refreshCards() }
            }.disabled(model.isSaving)
        }
    }
}

#Preview { NavigationStack { ReviewView(services: .preview()) } }
