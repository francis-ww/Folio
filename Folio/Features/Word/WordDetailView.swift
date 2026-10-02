import SwiftUI
import FolioCore

struct WordDetailView: View {
    let services: AppServices
    @State private var model: WordDetailViewModel
    @State private var linkedWord: DictionaryEntry?

    init(entry: DictionaryEntry, services: AppServices) {
        self.services = services
        _model = State(initialValue: WordDetailViewModel(entry: entry))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(LocalizedStringKey(model.entry.online == nil ? "THE DICTIONARY" : "YOUDAO · ENGLISH–CHINESE"))
                        .font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    Text(model.entry.headword.decodingHTMLEntities).font(Theme.display).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    if model.entry.online == nil {
                        HStack(spacing: 12) {
                            if !model.entry.pronunciation.isEmpty { Text(model.entry.pronunciation).font(.subheadline).foregroundStyle(Theme.muted) }
                            Button { model.pronounce() } label: { Image(systemName: "speaker.wave.2").font(.body).frame(width: 44, height: 44) }
                                .accessibilityLabel("Pronounce \(model.entry.headword.decodingHTMLEntities)")
                            Spacer()
                        }
                    }
                }
                Rectangle().fill(Theme.rule).frame(height: 1)
                SystemDictionaryAction(term: model.requestedHeadword)
                if model.isLoading { ProgressView("Looking across your dictionaries…") }
                if !model.results.isEmpty {
                    DictionaryResultTabs(results: model.results, selectedID: model.selectedSourceID, onSelect: model.select)
                }
                if !model.results.isEmpty || services.isSaved(model.entry) || model.isLoading {
                    if model.results.isEmpty && !model.isLoading {
                        Text("Saved definition").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text("Your saved copy remains available even when its dictionary is disabled or removed.")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    WordDefinitionContent(entry: model.entry, repository: services.dictionary, onLookup: { word in
                        navigateTo(word: word)
                    }, onNavigateToEntry: { word in
                        navigateTo(word: word)
                    }, onPronounce: { model.pronounce($0) }).id("\(model.entry.dictionaryID):\(services.libraryRevision)")
                    if model.audio.isLoading { ProgressView("Loading pronunciation…").font(.caption) }
                    if let error = model.audio.error { LocalizedMessageText(error).font(.subheadline).foregroundStyle(Theme.muted) }
                } else if !model.isLoading {
                    ContentUnavailableView(LocalizedStringKey(model.failures.isEmpty ? "No enabled dictionary has this word" : "No definition is available right now"), systemImage: "books.vertical",
                                           description: Text("Enable more sources in Library, or try the system dictionary."))
                }
                if !model.failures.isEmpty { DictionaryFailuresView(failures: model.failures) }
                if let error = model.error { LocalizedMessageText(error).font(.subheadline).foregroundStyle(Theme.error) }
            }.padding(Theme.margin).padding(.bottom, 20)
        }
        .background(Theme.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await model.save(using: services) } } label: {
                Label(LocalizedStringKey(model.isSaving ? "Saving…" : (services.isSaved(model.entry) ? "In your collection" : "Keep this word")),
                      systemImage: services.isSaved(model.entry) ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(model.isSaving || model.isLoading || model.results.isEmpty || services.isSaved(model.entry))
            .padding(.horizontal, Theme.margin).padding(.vertical, 12).background(Theme.paper)
        }
        .sensoryFeedback(.success, trigger: services.isSaved(model.entry))
        .task(id: services.libraryRevision) { await model.resolve(using: services.dictionary) }
        .onDisappear { model.stopSpeaking() }
        .navigationDestination(item: $linkedWord) { WordDetailView(entry: $0, services: services) }
    }

    private func navigateTo(word: String) {
        Task {
            do {
                let report = try await services.dictionary.lookupAll(word)
                try Task.checkCancellation()
                linkedWord = (report.results.first { $0.id == model.selectedSourceID } ?? report.results.first)?.entry
                if linkedWord == nil {
                    model.error = report.failures.first?.message ?? FolioMessage("No definition was found for %@.", [.text(word)])
                }
            } catch is CancellationError {} catch {
                model.error = FolioMessage.from(error, fallback: "This word couldn’t be opened or saved. Please try again.")
            }
        }
    }
}

#Preview { NavigationStack { WordDetailView(entry: SampleData.entries[0], services: .preview()) } }
#Preview("Online English–Chinese") { NavigationStack { WordDetailView(entry: SampleData.onlineEntry, services: .preview()) } }
