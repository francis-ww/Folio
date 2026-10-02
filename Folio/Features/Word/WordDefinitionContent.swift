import SwiftUI
import FolioCore

struct WordDefinitionContent: View {
    let entry: DictionaryEntry
    let repository: any DictionaryRepository
    let onLookup: @MainActor (String) -> Void
    let onPronounce: (URL) -> Void

    var body: some View {
        if let online = entry.online {
            OnlineDefinitionCardView(definition: online, phonetic: entry.pronunciation, onPronounce: onPronounce)
        } else if entry.html.isEmpty {
            NativeDefinition(entry: entry)
        } else if !entry.html.hasPrefix("@@@LINK=") {
            DictionaryHTMLView(entry: entry, repository: repository, onLookup: onLookup).frame(height: 480)
            Text("Scroll within the definition to read more.").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

#Preview { WordDefinitionContent(entry: SampleData.onlineEntry, repository: MockDictionaryRepository(), onLookup: { _ in }, onPronounce: { _ in }).padding().background(Theme.paper) }
