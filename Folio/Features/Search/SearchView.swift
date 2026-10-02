import SwiftUI
import FolioCore

struct SearchView: View {
    let services: AppServices
    @Environment(\.locale) private var locale
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
                    Text(LocalizedStringKey(model.query.isEmpty ? "EXPLORE THE DICTIONARY" : "SEARCH RESULTS"))
                        .font(.caption2.weight(.semibold)).tracking(1.6).foregroundStyle(Theme.muted)
                    Spacer()
                    if !model.isSearching { Text(model.results.count, format: .number).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted) }
                }
                if !model.failures.isEmpty { DictionaryFailuresView(failures: model.failures) }
                if let error = model.error {
                    ContentUnavailableView("Search unavailable", systemImage: "exclamationmark.magnifyingglass", description: Text(verbatim: AppLocalization.string(error, locale: locale)))
                    Button("Try again") { Task { await model.search() } }
                } else if model.results.isEmpty && !model.isSearching {
                    if model.failures.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "magnifyingglass", description: Text("No entries found for \(model.query)."))
                    } else {
                        ContentUnavailableView("No definition is available right now", systemImage: "books.vertical")
                        Button("Try again") { Task { await model.search() } }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(model.results) { entry in
                            NavigationLink(value: entry) { WordRow(entry: entry, isSaved: services.isSaved(entry), source: model.sources.first { $0.id == entry.dictionaryID }) }
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
