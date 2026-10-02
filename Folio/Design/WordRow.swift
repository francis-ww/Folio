import SwiftUI
import FolioCore

struct WordRow: View {
    let entry: DictionaryEntry
    var isSaved = false
    var source: DictionarySource? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                if let source { DictionarySourceTitle(source: source).font(.caption2).foregroundStyle(Theme.muted) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(entry.headword).font(Theme.headword).foregroundStyle(Theme.ink)
                    if !entry.partOfSpeech.isEmpty { Text(entry.partOfSpeech).font(.caption).italic().foregroundStyle(Theme.muted) }
                }
                Group {
                    if entry.dictionaryID == "youdao-online" && entry.online == nil { Text("Open this word to look up its online definition.") }
                    else { Text(entry.summary) }
                }.font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(3).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: isSaved ? "bookmark.fill" : "arrow.up.right")
                .font(.caption).foregroundStyle(isSaved ? Theme.accent : Theme.muted).padding(.top, 8)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 18).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(LocalizedStringKey(isSaved ? "Saved" : "")))
    }
}

#Preview { WordRow(entry: SampleData.entries[0], isSaved: true).padding().background(Theme.paper) }
