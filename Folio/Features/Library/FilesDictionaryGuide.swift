import SwiftUI

struct FilesDictionaryGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "folder").font(.title2).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text("Make room for your dictionaries.").font(Theme.headword).accessibilityAddTraits(.isHeader)
            Text("Open Files, go to On My iPhone → Folio, and paste your MDX and MDD files here. On iPad, look under On My iPad.")
                .font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
            Text("Use matching filenames, such as Oxford.mdx and Oxford.mdd. Return to Folio to start indexing, or tap Refresh Dictionaries.")
                .font(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
        }.fixedSize(horizontal: false, vertical: true).padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview { FilesDictionaryGuide().padding().background(Theme.paper) }
#Preview("简体中文 · Dark") {
    FilesDictionaryGuide().padding().background(Theme.paper)
        .environment(\.locale, Locale(identifier: "zh-Hans")).preferredColorScheme(.dark)
}
