import SwiftUI
import UIKit

struct SystemDictionaryAction: View {
    let term: String
    @State private var available = false
    @State private var presenting = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button { presenting = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "text.book.closed").font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("iOS System Dictionary").font(.subheadline.weight(.semibold))
                    Text(LocalizedStringKey(available ? "Read the definition in Apple’s reference library." : "No system definition is available for this word."))
                        .font(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption)
            }.foregroundStyle(available ? Theme.ink : Theme.muted).padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(!available)
            .task(id: term) { refresh() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
            .sheet(isPresented: $presenting) { SystemDictionarySheet(term: term).ignoresSafeArea() }
    }
    private func refresh() { available = UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) }
}

#Preview { SystemDictionaryAction(term: "serendipity").padding().background(Theme.paper) }
