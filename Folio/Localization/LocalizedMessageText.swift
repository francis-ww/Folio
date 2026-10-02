import SwiftUI
import FolioCore

struct LocalizedMessageText: View {
    let message: FolioMessage
    @Environment(\.locale) private var locale

    init(_ message: FolioMessage) { self.message = message }

    var body: some View { Text(verbatim: AppLocalization.string(message, locale: locale)) }
}

#Preview("简体中文") {
    LocalizedMessageText(FolioMessage("Your dictionary is ready."))
        .environment(\.locale, Locale(identifier: "zh-Hans")).padding()
}
