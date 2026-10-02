import SwiftUI
import UniformTypeIdentifiers
import FolioCore

struct LibraryView: View {
    let services: AppServices
    @State private var model = LibraryViewModel()
    @State private var showingImporter = false
    @State private var removing: DictionarySource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                EditorialHeader(eyebrow: "Always within reach", title: "Your reference\nshelf.", subtitle: "Bring your dictionaries. Explore them offline.")
                DictionarySelectionView(sources: model.sources, selection: model.selection, onToggle: { id, enabled in
                    model.setEnabled(enabled, id: id, services: services)
                }, onMove: { offsets, destination in
                    var ids = model.sources.map(\.id)
                    ids.move(fromOffsets: offsets, toOffset: destination)
                    model.reorder(ids, services: services)
                }, onRemove: { removing = $0 })
                Button { showingImporter = true } label: { Label("Import dictionaries", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.isImporting || services.library == nil)
                if model.isImporting {
                    HStack {
                        ProgressView()
                        LocalizedMessageText(model.status ?? FolioMessage("Importing…")).font(.subheadline)
                    }
                    Button("Cancel import", role: .cancel) { model.cancelImport() }.font(.subheadline)
                } else if let status = model.status { LocalizedMessageText(status).font(.subheadline).foregroundStyle(Theme.accent) }
                if let error = model.error { LocalizedMessageText(error).font(.subheadline).foregroundStyle(Theme.error) }
                LanguageSettingsView(manager: services.language)
                AppearanceSettingsView(manager: services.appearance)
                OnlineDictionarySettingsView(services: services, isEnabled: model.selection.isEnabled(DictionarySource.youdao.id))
                VStack(alignment: .leading, spacing: 12) {
                    Text("A NOTE ON YOUR LIBRARY").font(.caption2.weight(.semibold)).tracking(1.5)
                    Text("Choose an MDX file and its matching MDD resource file together. Their filenames should match, for example Oxford.mdx and Oxford.mdd.")
                    Text("Supports MDict v2 dictionaries in UTF-8 or UTF-16, including self-contained encryption, with zlib or no compression. Dictionaries requiring a registration passcode, LZO, and embedded stylesheet substitutions are not supported yet.")
                    Text("Saved words and practice history stay on this device. Deleting a dictionary keeps your saved definitions.")
                }.font(.caption).foregroundStyle(Theme.muted).lineSpacing(4).padding(.top, 8)
            }.padding(.horizontal, Theme.margin).padding(.bottom, 30)
        }.background(Theme.paper).toolbar(.hidden, for: .navigationBar)
            .task { await model.refresh(services) }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [UTType(filenameExtension: "mdx") ?? .data, UTType(filenameExtension: "mdd") ?? .data],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): model.importFiles(urls, services: services)
                case .failure(let error): model.error = FolioMessage.from(error, fallback: "The selected files couldn’t be opened. Please try again.")
                }
            }
            .confirmationDialog("Remove \(removing?.title ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove dictionary and resources", role: .destructive) {
                    guard let source = removing else { return }
                    Task { await model.remove(source, services: services) }
                    removing = nil
                }
            }
    }
}

#Preview { NavigationStack { LibraryView(services: .preview()) } }
