import SwiftUI
import FolioCore

struct FeaturedWordCard: View {
    let entry: DictionaryEntry
    var body: some View {
        NavigationLink(value: entry) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("THE EDITOR’S PICK").font(.caption2.weight(.semibold)).tracking(1.8)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.foregroundStyle(Theme.accent)
                Text(entry.headword.decodingHTMLEntities).font(Theme.title).foregroundStyle(Theme.ink)
                Text(entry.summary).font(.subheadline).lineSpacing(4).foregroundStyle(Theme.muted)
                Text("From the Folio sample dictionary").font(.caption2).foregroundStyle(Theme.muted)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.15), lineWidth: 1) }
        }.buttonStyle(.plain)
    }
}

#Preview { NavigationStack { FeaturedWordCard(entry: SampleData.entries[0]).padding().background(Theme.paper) } }
