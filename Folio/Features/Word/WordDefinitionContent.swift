import SwiftUI
import FolioCore

struct WordDefinitionContent: View {
    let entry: DictionaryEntry
    let repository: any DictionaryRepository
    var onLookup: @MainActor (String) -> Void = { _ in }
    var onNavigateToEntry: (@MainActor (String) -> Void)? = nil
    let onPronounce: (URL) -> Void
    @State private var resourceFailure: FolioMessage?

    var body: some View {
        if let online = entry.online {
            OnlineDefinitionCardView(definition: online, phonetic: entry.pronunciation, onPronounce: onPronounce)
        } else if entry.html.isEmpty {
            NativeDefinition(entry: entry)
        } else if !entry.html.hasPrefix("@@@LINK=") {
            DictionaryHTMLView(
                entry: entry,
                repository: repository,
                onLookup: onLookup,
                onNavigateToEntry: onNavigateToEntry,
                onResourceFailure: { resourceFailure = $0 }
            ).frame(height: 480)
            if let resourceFailure { DictionaryImportWarningView(messages: [resourceFailure]) }
            Text("Scroll within the definition to read more.").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

#Preview { WordDefinitionContent(entry: SampleData.onlineEntry, repository: MockDictionaryRepository(), onLookup: { _ in }, onPronounce: { _ in }).padding().background(Theme.paper) }
