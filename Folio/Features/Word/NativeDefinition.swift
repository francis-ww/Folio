import SwiftUI
import FolioCore

struct NativeDefinition: View {
    let entry: DictionaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !entry.partOfSpeech.isEmpty { Text(entry.partOfSpeech).font(.subheadline).italic().foregroundStyle(Theme.accent) }
            HStack(alignment: .top, spacing: 14) {
                Text("01").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted).padding(.top, 5)
                Text(entry.summary).font(.title3).lineSpacing(6).textSelection(.enabled)
            }
            if !entry.example.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2)
                    Text(entry.example).font(.body).italic().foregroundStyle(Theme.muted).lineSpacing(5)
                }.fixedSize(horizontal: false, vertical: true).padding(.leading, 32)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview { NativeDefinition(entry: SampleData.entries[0]).padding().background(Theme.paper) }
