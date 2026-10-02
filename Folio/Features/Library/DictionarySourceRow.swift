import SwiftUI
import FolioCore

struct DictionarySourceRow: View {
    let source: DictionarySource
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "book.closed").font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 48, height: 60).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Group { if source.isSample { Text("Folio sample dictionary") } else { Text(source.title) } }.font(.headline)
                (Text("\(source.entryCount) entries") + Text(verbatim: " · ") + Text("\(source.resourceCount) resources"))
                    .font(.caption).foregroundStyle(Theme.muted)
                Text(LocalizedStringKey(source.isSample ? "SAMPLE DICTIONARY" : "AVAILABLE OFFLINE"))
                    .font(.caption2.weight(.medium)).tracking(1).foregroundStyle(Theme.accent)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.rule, lineWidth: 1) }
            .accessibilityElement(children: .combine)
    }
}

#Preview { DictionarySourceRow(source: .init(id: "sample", title: "Folio sample dictionary", filename: "sample", entryCount: 8, isSample: true)).padding().background(Theme.paper) }
