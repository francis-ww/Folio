import SwiftUI
import FolioCore

struct ReviewCardView: View {
    let card: VocabularyCard
    let isRevealed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                Text(LocalizedStringKey(card.memory.state == .new ? "A NEW WORD" : "A FAMILIAR WORD"))
                    .font(.caption2.weight(.semibold)).tracking(1.5)
                Spacer()
                Image(systemName: "bookmark")
            }.foregroundStyle(Theme.muted)
            Text(card.entry.headword).font(Theme.title).accessibilityAddTraits(.isHeader)
            if !card.entry.pronunciation.isEmpty { Text(card.entry.pronunciation).font(.subheadline).foregroundStyle(Theme.muted) }
            Rectangle().fill(Theme.rule).frame(height: 1)
            if isRevealed {
                if let online = card.entry.online {
                    OnlineDefinitionCardView(definition: online, phonetic: card.entry.pronunciation)
                } else if card.entry.dictionaryID == "youdao-online" {
                    NavigationLink(value: card.entry) { Label("Look up this word", systemImage: "globe") }
                        .font(.body).foregroundStyle(Theme.accent)
                } else { NativeDefinition(entry: card.entry) }
            } else {
                Text(LocalizedStringKey("What does this word mean to you?")).font(.body).foregroundStyle(Theme.muted).padding(.vertical, 20)
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 300, alignment: .top)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.rule, lineWidth: 1) }
    }
}

#Preview { ReviewCardView(card: SampleData.cards()[0], isRevealed: true).padding().background(Theme.paper) }
