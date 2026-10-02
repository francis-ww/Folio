import SwiftUI
import FolioCore

struct DictionaryImportWarningView: View {
    let messages: [FolioMessage]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Failed to parse dictionary", systemImage: "exclamationmark.triangle")
                .font(.headline).foregroundStyle(Theme.error).accessibilityAddTraits(.isHeader)
            Text("Available definitions remain readable. Check the files, then refresh to try again.")
                .font(.subheadline).foregroundStyle(Theme.muted)
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                LocalizedMessageText(message).font(.caption).foregroundStyle(Theme.muted)
            }
        }.fixedSize(horizontal: false, vertical: true).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.error.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    DictionaryImportWarningView(messages: [FolioMessage("A dictionary file is still changing. Let the copy finish, then scan again.")])
        .padding().background(Theme.paper)
}
#Preview("简体中文 · Dark") {
    DictionaryImportWarningView(messages: [MDictError.passcodeRequired.message]).padding().background(Theme.paper)
        .environment(\.locale, Locale(identifier: "zh-Hans")).preferredColorScheme(.dark)
}
