import SwiftUI
import FolioCore

struct DictionaryResultTabs: View {
    let results: [DictionaryLookupResult]
    let selectedID: String?
    let onSelect: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(results) { result in
                    Button { onSelect(result.id) } label: {
                        DictionarySourceTitle(source: result.source)
                            .font(.subheadline.weight(result.id == selectedID ? .semibold : .regular))
                            .foregroundStyle(result.id == selectedID ? Theme.ink : Theme.muted)
                            .padding(.vertical, 14)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(result.id == selectedID ? Theme.accent : .clear).frame(height: 2)
                            }
                    }.buttonStyle(.plain).accessibilityAddTraits(result.id == selectedID ? .isSelected : [])
                }
            }
        }.accessibilityElement(children: .contain)
    }
}

#Preview { DictionaryResultTabs(results: [.init(source: .youdao, entry: SampleData.onlineEntry)], selectedID: "youdao-online", onSelect: { _ in }).padding().background(Theme.paper) }
