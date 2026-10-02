import SwiftUI
import FolioCore

struct CollectionView: View {
    let services: AppServices
    @State private var query = ""
    @State private var removing: VocabularyCard?
    private var visibleCards: [VocabularyCard] {
        services.cards.filter { query.isEmpty || $0.entry.headword.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorialHeader(eyebrow: "Your personal lexicon", title: "Collected,\nwith care.", subtitle: "\(services.cards.count) words worth returning to.")
                if services.cards.isEmpty {
                    ContentUnavailableView("A collection begins with one word.", systemImage: "bookmark", description: Text("Tap Keep this word on a definition to save it here."))
                } else {
                    SearchField(query: $query)
                    LazyVStack(spacing: 0) {
                        ForEach(visibleCards) { card in
                            NavigationLink(value: card.entry) { WordRow(entry: card.entry, isSaved: true) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Remove word", role: .destructive) { removing = card } }
                            HStack {
                                if card.memory.state == .new { Text("New") }
                                else { Text("\(card.memory.repetitions) reviews") }
                                Spacer()
                                if card.memory.due <= .now { Text("Ready to practice").foregroundStyle(Theme.accent) }
                                else { Text(card.memory.due, style: .relative) }
                            }.font(.caption2).foregroundStyle(Theme.muted).padding(.bottom, 16)
                            Rectangle().fill(Theme.rule).frame(height: 1)
                        }
                    }
                    if visibleCards.isEmpty { ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("No entries found for \(query).")) }
                }
            }.padding(.horizontal, Theme.margin).padding(.bottom, 30)
        }.background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .task { await services.refreshCards() }
            .scrollDismissesKeyboard(.interactively)
            .confirmationDialog("Remove \(removing?.entry.headword.decodingHTMLEntities ?? "") from your collection?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove word and review history", role: .destructive) {
                    guard let card = removing else { return }
                    Task {
                        do { try await services.vocabulary.remove(id: card.id); await services.refreshCards() }
                        catch { services.error = FolioMessage.from(error, fallback: "This word couldn’t be removed. Please try again.") }
                    }
                    removing = nil
                }
            }
    }
}

#Preview { NavigationStack { CollectionView(services: .preview()) } }
