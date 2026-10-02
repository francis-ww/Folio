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
                    Text("THE DICTIONARY").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.muted)
                    Text(model.entry.headword).font(Theme.display).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: 12) {
                        if !model.entry.pronunciation.isEmpty { Text(model.entry.pronunciation).font(.subheadline).foregroundStyle(Theme.muted) }
                        Button { model.pronounce() } label: { Image(systemName: "speaker.wave.2").font(.body).frame(width: 44, height: 44) }
                            .accessibilityLabel("Pronounce \(model.entry.headword)")
                        Spacer()
                    }
                }
                Rectangle().fill(Theme.rule).frame(height: 1)
                if model.entry.html.isEmpty {
                    NativeDefinition(entry: model.entry)
                } else if !model.entry.html.hasPrefix("@@@LINK=") {
                    DictionaryHTMLView(entry: model.entry, repository: services.dictionary) { word in
                        Task {
                            do {
                                linkedWord = try await services.dictionary.lookup(word, dictionaryID: model.entry.dictionaryID)
                                if linkedWord == nil { model.error = "No definition was found for \(word)." }
                            } catch { model.error = error.localizedDescription }
                        }
                    }
                    .frame(height: 480)
                    Text("Scroll within the definition to read more.").font(.caption).foregroundStyle(Theme.muted)
                }
                if let error = model.error { Text(error).font(.subheadline).foregroundStyle(.red) }
            }.padding(Theme.margin).padding(.bottom, 20)
        }
        .background(Theme.paper)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await model.save(using: services) } } label: {
                Label(model.isSaving ? "Saving…" : (services.isSaved(model.entry) ? "In your collection" : "Keep this word"),
                      systemImage: services.isSaved(model.entry) ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(PrimaryButtonStyle()).disabled(model.isSaving || services.isSaved(model.entry))
            .padding(.horizontal, Theme.margin).padding(.vertical, 12).background(Theme.paper)
        }
        .sensoryFeedback(.success, trigger: services.isSaved(model.entry))
        .task { await model.resolve(using: services.dictionary) }
        .onDisappear { model.stopSpeaking() }
        .navigationDestination(item: $linkedWord) { WordDetailView(entry: $0, services: services) }
    }
}

#Preview { NavigationStack { WordDetailView(entry: SampleData.entries[0], services: .preview()) } }
