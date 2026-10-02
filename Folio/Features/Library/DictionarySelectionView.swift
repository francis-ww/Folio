import SwiftUI
import FolioCore

struct DictionarySelectionView: View {
    let sources: [DictionarySource]
    let selection: DictionarySelection
    let onToggle: (String, Bool) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onRemove: (DictionarySource) -> Void
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Dictionary sources").font(Theme.headword).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Reorder") { editing = true }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            Text("Enable the sources you want to read. Drag to set their order.")
                .font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 12) {
                ForEach(sources) { source in
                    Toggle(isOn: Binding(get: { selection.isEnabled(source.id) }, set: { onToggle(source.id, $0) })) {
                        VStack(alignment: .leading, spacing: 6) {
                            DictionarySourceTitle(source: source).font(.headline)
                            if source.isOnline { Text("English–Chinese · Online").font(.caption).foregroundStyle(Theme.muted) }
                            else { Text("\(source.entryCount) entries").font(.caption).foregroundStyle(Theme.muted) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.tint(Theme.accent).padding(18)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .contextMenu {
                            if !source.isSample && !source.isOnline {
                                Button("Remove dictionary", role: .destructive) { onRemove(source) }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                List {
                    ForEach(sources) { source in
                        DictionarySourceTitle(source: source).padding(.vertical, 8).listRowBackground(Theme.surface)
                    }.onMove(perform: onMove)
                }.environment(\.editMode, .constant(.active)).scrollContentBackground(.hidden)
                    .background(Theme.paper).navigationTitle("Dictionary order")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
            }
        }
    }
}

#Preview {
    DictionarySelectionView(sources: [.youdao, .init(id: "sample", title: "Folio sample dictionary", filename: "sample", entryCount: 8, isSample: true)],
                            selection: .init(), onToggle: { _, _ in }, onMove: { _, _ in }, onRemove: { _ in })
        .padding().background(Theme.paper)
}
