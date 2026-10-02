import SwiftUI

struct SearchField: View {
    @Binding var query: String
    var isSearching = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("A word on your mind…", text: $query)
                .font(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search).accessibilityLabel("Search dictionary")
            if isSearching { ProgressView().controlSize(.small) }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .frame(minWidth: 44, minHeight: 44).accessibilityLabel("Clear search")
            }
        }.padding(.leading, 18).padding(.trailing, 8).frame(minHeight: 58)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(Theme.rule, lineWidth: 1) }
    }
}

#Preview { SearchField(query: .constant("seren")).padding().background(Theme.paper) }
