import SwiftUI
import FolioCore

@main
struct FolioApp: App {
    var body: some Scene { WindowGroup { AppBootstrapView() } }
}

private struct AppBootstrapView: View {
    @State private var services: AppServices?
    @State private var error: FolioMessage?
    @State private var language = AppLanguageManager()
    @State private var appearance = AppAppearanceManager()
    @State private var attempt = 0

    var body: some View {
        Group {
            if let services { RootView(services: services) }
            else if let error {
                ContentUnavailableView {
                    Label("Unable to open Folio", systemImage: "book.closed")
                } description: { LocalizedMessageText(error) } actions: {
                    Button("Try again") { self.error = nil; attempt += 1 }
                }
            } else {
                VStack(spacing: 20) {
                    Text("Folio").font(Theme.display)
                    ProgressView().tint(Theme.ink)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
            }
        }
        .tint(Theme.ink)
        .environment(\.locale, language.currentLocale)
        .preferredColorScheme(appearance.selection.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in language.refreshSystemLocale() }
        .task(id: attempt) {
            guard services == nil else { return }
            do { services = try await AppServices.makeLive(language: language, appearance: appearance) }
            catch { self.error = FolioMessage.from(error, fallback: "Folio couldn’t open its library. Please try again.") }
        }
    }
}

#Preview { RootView(services: .preview()) }
