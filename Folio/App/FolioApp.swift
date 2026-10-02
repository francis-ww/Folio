import SwiftUI

@main
struct FolioApp: App {
    var body: some Scene { WindowGroup { AppBootstrapView() } }
}

private struct AppBootstrapView: View {
    @State private var services: AppServices?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let services { RootView(services: services) }
            else if let error {
                ContentUnavailableView {
                    Label("Unable to open Folio", systemImage: "book.closed")
                } description: { Text(error) } actions: {
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
        .task(id: attempt) {
            guard services == nil else { return }
            do { services = try await AppServices.makeLive() }
            catch { self.error = error.localizedDescription }
        }
    }
}

#Preview { RootView(services: .preview()) }
