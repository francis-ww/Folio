import SwiftUI
import FolioCore

struct OnlineDefinitionCardView: View {
    let definition: OnlineDefinition
    var phonetic = ""
    var onPronounce: ((URL) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            if definition.ukPhonetic.isEmpty && definition.usPhonetic.isEmpty && !phonetic.isEmpty {
                Text(phonetic).font(.subheadline).foregroundStyle(Theme.muted).textSelection(.enabled)
            }
            VStack(spacing: 0) {
                if !definition.ukPhonetic.isEmpty || definition.ukAudioURL != nil {
                    OnlinePronunciationView(accent: "UK", phonetic: definition.ukPhonetic,
                                            audioURL: definition.ukAudioURL, onPronounce: onPronounce)
                }
                if !definition.usPhonetic.isEmpty || definition.usAudioURL != nil {
                    OnlinePronunciationView(accent: "US", phonetic: definition.usPhonetic,
                                            audioURL: definition.usAudioURL, onPronounce: onPronounce)
                }
                if let url = definition.audioURL {
                    OnlinePronunciationView(accent: "EN", phonetic: "", audioURL: url, onPronounce: onPronounce)
                }
            }
            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(definition.meanings.enumerated()), id: \.offset) { index, meaning in
                    HStack(alignment: .top, spacing: 14) {
                        Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.muted).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 8) {
                            if !meaning.partOfSpeech.isEmpty {
                                Text(meaning.partOfSpeech).font(.subheadline).italic().foregroundStyle(Theme.accent)
                            }
                            Text(meaning.text).font(.title3).lineSpacing(6).textSelection(.enabled)
                        }
                    }
                }
            }
            if !definition.webTranslations.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("WEB TRANSLATIONS")
                    ForEach(Array(definition.webTranslations.enumerated()), id: \.offset) { _, value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(value.phrase).font(.body.weight(.medium))
                            Text(value.translations.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
                        }.textSelection(.enabled)
                    }
                }
            }
            if !definition.examples.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    sectionLabel("IN CONTEXT")
                    ForEach(Array(definition.examples.enumerated()), id: \.offset) { _, example in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(example.sentence).font(.custom("Georgia", size: 18, relativeTo: .body)).italic().lineSpacing(5)
                            Text(example.translation).font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
                        }.textSelection(.enabled).padding(.leading, 16)
                            .overlay(alignment: .leading) { Rectangle().fill(Theme.accent.opacity(0.4)).frame(width: 2) }
                    }
                }
            }
            Text("有道 · Youdao").font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ value: LocalizedStringKey) -> some View {
        Text(value).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(Theme.muted)
    }
}

#Preview {
    ScrollView { OnlineDefinitionCardView(definition: SampleData.onlineEntry.online!).padding(Theme.margin) }.background(Theme.paper)
}
