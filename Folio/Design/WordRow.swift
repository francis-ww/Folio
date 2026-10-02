import SwiftUI
import FolioCore

struct WordRow: View {
    let entry: DictionaryEntry
    var isSaved = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.headword).font(Theme.headword).foregroundStyle(Theme.ink)
                    if !entry.partOfSpeech.isEmpty { Text(entry.partOfSpeech).font(.caption).italic().foregroundStyle(Theme.muted) }
                }
                Text(entry.summary).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(3).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isSaved ? "bookmark.fill" : "arrow.up.right")
                .font(.caption).foregroundStyle(isSaved ? Theme.accent : Theme.muted).padding(.top, 8)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 18).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isSaved ? "Saved" : "")
    }
}

#Preview { WordRow(entry: SampleData.entries[0], isSaved: true).padding().background(Theme.paper) }
