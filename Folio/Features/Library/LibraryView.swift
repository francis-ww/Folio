import SwiftUI
import UIKit
import FolioCore

struct LibraryView: View {
    let services: AppServices
    @State private var model = LibraryViewModel()
    @State private var removing: DictionarySource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                EditorialHeader(eyebrow: "Always within reach", title: "Your reference\nshelf.", subtitle: "Bring your dictionaries. Explore them offline.")
                if !model.sources.contains(where: { !$0.isSample && !$0.isOnline }) {
                    FilesDictionaryGuide()
                }
                Button {
                    Task { await services.scanDocuments(); await model.refresh(services) }
                } label: { Label("Refresh Dictionaries", systemImage: "arrow.clockwise") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(services.isScanningDocuments || services.documentsScanner == nil)
                Button { Task { await openFiles() } } label: { Label("Open Files App", systemImage: "folder") }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                if services.isScanningDocuments {
                    HStack(alignment: .top, spacing: 12) {
                        ProgressView()
                        Text("Reading new dictionaries in the background…").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                } else if let status = services.documentsStatus {
                    LocalizedMessageText(status).font(.subheadline).foregroundStyle(Theme.accent)
                }
                ForEach(Array(services.documentsFailures.enumerated()), id: \.offset) { _, message in
                    LocalizedMessageText(message).font(.subheadline).foregroundStyle(Theme.error)
                }
                DictionarySelectionView(sources: model.sources, selection: model.selection, onToggle: { id, enabled in
                    model.setEnabled(enabled, id: id, services: services)
                }, onMove: { offsets, destination in
                    var ids = model.sources.map(\.id)
                    ids.move(fromOffsets: offsets, toOffset: destination)
                    model.reorder(ids, services: services)
                }, onRemove: { removing = $0 }, allowsRemoval: !services.isScanningDocuments)
                if let error = model.error { LocalizedMessageText(error).font(.subheadline).foregroundStyle(Theme.error) }
                LanguageSettingsView(manager: services.language)
                AppearanceSettingsView(manager: services.appearance)
                OnlineDictionarySettingsView(services: services, isEnabled: model.selection.isEnabled(DictionarySource.youdao.id))
                VStack(alignment: .leading, spacing: 12) {
                    Text("A NOTE ON YOUR LIBRARY").font(.caption2.weight(.semibold)).tracking(1.5)
                    Text("Folio scans its Documents folder when you open the app. Unchanged files are skipped. Keep dictionary files directly inside Folio’s folder.")
                    Text("Supports MDict v2 dictionaries in UTF-8 or UTF-16, including self-contained encryption, with zlib or no compression. Dictionaries requiring a registration passcode, LZO, and embedded stylesheet substitutions are not supported yet.")
                    Text("Removing a dictionary also deletes its MDX and matching MDD files from Folio’s folder. Your saved words and practice history stay on this device.")
                }.font(.caption).foregroundStyle(Theme.muted).lineSpacing(4).padding(.top, 8)
            }.padding(.horizontal, Theme.margin).padding(.bottom, 30)
        }.background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .task(id: services.libraryRevision) { await model.refresh(services) }
            .refreshable { await services.scanDocuments(); await model.refresh(services) }
            .confirmationDialog("Remove \(removing?.title ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove dictionary and resources", role: .destructive) {
                    guard let source = removing else { return }
                    Task { await model.remove(source, services: services) }
                    removing = nil
                }
            }
    }

    @MainActor private func openFiles() async {
        guard let url = URL(string: "shareddocuments://") else { return }
        if !(await UIApplication.shared.open(url)) {
            model.error = FolioMessage("Open the Files app from your Home Screen, then go to On My iPhone → Folio.")
        }
    }
}

#Preview { NavigationStack { LibraryView(services: .preview()) } }
