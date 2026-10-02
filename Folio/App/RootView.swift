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
            }.tabItem { Label("Discover", systemImage: "magnifyingglass") }
            NavigationStack { ReviewView(services: services) }
                .tabItem { Label("Practice", systemImage: "rectangle.on.rectangle") }
                .badge(services.dueCount)
            NavigationStack {
                CollectionView(services: services)
                    .navigationDestination(for: DictionaryEntry.self) { WordDetailView(entry: $0, services: services) }
            }.tabItem { Label("Collection", systemImage: "bookmark") }
            NavigationStack { LibraryView(services: services) }
                .tabItem { Label("Library", systemImage: "books.vertical") }
        }
        .tint(Theme.ink)
        .task { await services.refreshCards() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await services.refreshCards() } }
        }
        .alert("Something needs attention", isPresented: Binding(get: { services.error != nil }, set: { if !$0 { services.error = nil } })) {
            Button("OK", role: .cancel) { services.error = nil }
        } message: { Text(services.error ?? "") }
    }
}

#Preview { RootView(services: .preview()) }
