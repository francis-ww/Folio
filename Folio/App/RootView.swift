import SwiftUI
import FolioCore

struct RootView: View {
    @Bindable var services: AppServices
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            NavigationStack {
                SearchView(services: services)
                    .navigationDestination(for: DictionaryEntry.self) { WordDetailView(entry: $0, services: services) }
            }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            NavigationStack {
                ReviewView(services: services)
                    .navigationDestination(for: DictionaryEntry.self) { WordDetailView(entry: $0, services: services) }
            }
                .tabItem { Label("Review", systemImage: "rectangle.on.rectangle") }
                .badge(services.dueCount)
            NavigationStack {
                CollectionView(services: services)
                    .navigationDestination(for: DictionaryEntry.self) { WordDetailView(entry: $0, services: services) }
            }.tabItem { Label("Collection", systemImage: "bookmark") }
            NavigationStack { LibraryView(services: services) }
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .tint(Theme.ink)
        .task {
            await services.refreshCards()
            await services.scanDocuments()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                services.language.refreshSystemLocale()
                Task { await services.refreshCards(); await services.scanDocuments() }
            }
        }
        .alert("Something needs attention", isPresented: Binding(get: { services.error != nil }, set: { if !$0 { services.error = nil } })) {
            Button("OK", role: .cancel) { services.error = nil }
        } message: { if let error = services.error { LocalizedMessageText(error) } }
        .environment(\.locale, services.language.currentLocale)
        .preferredColorScheme(services.appearance.selection.colorScheme)
    }
}

#Preview { RootView(services: .preview()) }
#Preview("简体中文") {
    RootView(services: .preview(language: .simplifiedChinese))
}
