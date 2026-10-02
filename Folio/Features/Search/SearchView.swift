import SwiftUI
import FolioCore

struct SearchView: View {
    let services: AppServices
    @State private var model: SearchViewModel

    init(services: AppServices) {
        self.services = services
        _model = State(initialValue: SearchViewModel(dictionary: services.dictionary))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditorialHeader(eyebrow: "Folio · a companion for curious minds", title: "Words, worth\nkeeping.", subtitle: "Find a meaning. Keep a little wonder.")
                SearchField(query: $model.query, isSearching: model.isSearching)
                if model.query.isEmpty { FeaturedWordCard(entry: SampleData.entries[0]) }
                HStack {
                    Text(model.query.isEmpty ? "EXPLORE THE DICTIONARY" : "SEARCH RESULTS")
                        .font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.muted)
                    Spacer()
                    if !model.isSearching { Text("\(model.results.count)").font(.caption.monospacedDigit()).foregroundStyle(Theme.muted) }
                }
                if let error = model.error {
                    ContentUnavailableView("Search unavailable", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
                    Button("Try again") { Task { await model.search() } }
                } else if model.results.isEmpty && !model.isSearching {
                    ContentUnavailableView.search(text: model.query)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { entry in
                            NavigationLink(value: entry) { WordRow(entry: entry, isSaved: services.isSaved(entry)) }
                                .buttonStyle(.plain)
                            Rectangle().fill(Theme.rule).frame(height: 1).accessibilityHidden(true)
                        }
                    }
                }
            }.padding(.horizontal, Theme.margin).padding(.bottom, 30)
        }
        .background(Theme.paper).toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .task(id: "\(services.libraryRevision):\(model.query)") { await model.search() }
    }
}

#Preview { NavigationStack { SearchView(services: .preview()) } }
