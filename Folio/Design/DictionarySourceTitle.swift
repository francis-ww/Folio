import SwiftUI
import FolioCore

struct DictionarySourceTitle: View {
    let source: DictionarySource
    var body: some View {
        if source.isOnline { Text("Youdao") }
        else if source.isSample { Text("Folio sample dictionary") }
        else { Text(verbatim: source.title) }
    }
}

#Preview { DictionarySourceTitle(source: .youdao).padding() }
