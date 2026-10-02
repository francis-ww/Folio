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
                ForEach(model.sources) { source in
                    DictionarySourceRow(source: source)
                        .contextMenu {
                            if !source.isSample {
                                Button("Remove dictionary", role: .destructive) { removing = source }
                            }
                        }
                }
                Button { showingImporter = true } label: { Label("Import dictionaries", systemImage: "plus") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.isImporting || services.library == nil)
                if model.isImporting {
                    HStack {
                        ProgressView()
                        Text(model.status ?? "Importing…").font(.subheadline)
                    }
                    Button("Cancel import", role: .cancel) { model.cancelImport() }.font(.subheadline)
                } else if let status = model.status { Text(status).font(.subheadline).foregroundStyle(Theme.accent) }
                if let error = model.error { Text(error).font(.subheadline).foregroundStyle(.red) }
                VStack(alignment: .leading, spacing: 12) {
                    Text("A NOTE ON YOUR LIBRARY").font(.caption2.weight(.semibold)).tracking(1.5)
                    Text("Choose an MDX file and its matching MDD resource file together. Their filenames should match, for example Oxford.mdx and Oxford.mdd.")
                    Text("Supports unencrypted MDict v2 dictionaries in UTF-8 or UTF-16, with zlib or no compression. LZO and embedded stylesheet substitutions are not supported yet.")
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
                case .failure(let error): model.error = error.localizedDescription
                }
            }
            .confirmationDialog("Remove \(removing?.title ?? "this dictionary")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove dictionary and resources", role: .destructive) {
                    guard let source = removing else { return }
                    Task { await model.remove(source, services: services) }
                    removing = nil
                }
            }
    }
}

#Preview { NavigationStack { LibraryView(services: .preview()) } }
