import SwiftUI
import FolioCore

struct DictionaryFailuresView: View {
    let failures: [DictionarySourceFailure]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(failures) { failure in
                VStack(alignment: .leading, spacing: 6) {
                    DictionarySourceTitle(source: failure.source).font(.subheadline.weight(.semibold))
                    LocalizedMessageText(failure.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(Theme.muted)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .contain)
    }
}

#Preview { DictionaryFailuresView(failures: [.init(source: .youdao, message: YoudaoError.offline.message)]).padding().background(Theme.paper) }
