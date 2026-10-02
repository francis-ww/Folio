import SwiftUI
import FolioCore

struct OnlinePronunciationView: View {
    let accent: String
    @Environment(\.locale) private var locale
    let phonetic: String
    let audioURL: URL?
    var onPronounce: ((URL) -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(accent)).font(.caption.weight(.semibold)).tracking(1.2).frame(minWidth: 28, alignment: .leading)
            if !phonetic.isEmpty { Text(phonetic.hasPrefix("/") ? phonetic : "/\(phonetic)/").font(.subheadline).textSelection(.enabled) }
            Spacer(minLength: 8)
            if let audioURL, let onPronounce {
                Button { onPronounce(audioURL) } label: {
                    Image(systemName: "speaker.wave.2").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text(verbatim: AppLocalization.string(FolioMessage("Play %@ pronunciation", [.message(FolioMessage(accent))]), locale: locale)))
            }
        }.foregroundStyle(Theme.muted)
    }
}

#Preview { OnlinePronunciationView(accent: "UK", phonetic: "ɪˈfem.ər.əl", audioURL: nil).padding().background(Theme.paper) }
