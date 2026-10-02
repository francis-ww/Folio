import SwiftUI
import FolioCore

struct OnlineDictionarySettingsView: View {
    let services: AppServices
    var isEnabled = true
    @State private var model = OnlineDictionarySettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Online Dictionary Settings").font(Theme.headword).accessibilityAddTraits(.isHeader)
            Label(LocalizedStringKey(!isEnabled ? "Youdao Online · Disabled" : (model.isConfigured ? "Youdao Online Active (Default)" : "Youdao Online · Setup required")),
                  systemImage: !isEnabled ? "pause.circle" : (model.isConfigured ? "checkmark.circle.fill" : "globe"))
                .font(.subheadline).foregroundStyle(Theme.accent)
            Text("Enable Youdao alongside your local dictionaries to read English–Chinese results in your preferred source order.")
                .font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
            VStack(alignment: .leading, spacing: 8) {
                Text("App Key").font(.caption).foregroundStyle(Theme.muted)
                TextField("Your Youdao App Key", text: $model.appKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                Divider()
                Text("App Secret").font(.caption).foregroundStyle(Theme.muted)
                SecureField("Your Youdao App Secret", text: $model.appSecret)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
            }.padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 10))
            Picker("Youdao service", selection: $model.api) {
                ForEach(YoudaoAPI.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
            }.pickerStyle(.segmented)
            Text(LocalizedStringKey(model.api == .dictionary
                 ? "Dictionary API access enables richer definitions and examples. Saved words are kept as bookmarks and looked up again when opened."
                 : "The Text API returns Chinese translations. Phonetics, web meanings, and examples appear when provided by Youdao."))
                .font(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
            HStack(spacing: 18) {
                Button("Save keys") { Task { await model.save(services) } }
                    .font(.subheadline.weight(.semibold)).disabled(model.isWorking)
                if model.isConfigured {
                    Button("Remove keys", role: .destructive) { Task { await model.remove(services) } }
                        .font(.subheadline).disabled(model.isWorking)
                }
                if model.isWorking { ProgressView() }
            }
            if let status = model.status { LocalizedMessageText(status).font(.caption).foregroundStyle(Theme.accent) }
            Link("Get Youdao developer keys", destination: URL(string: "https://ai.youdao.com/")!)
                .font(.caption)
            Text("Your keys stay in this device’s Keychain. Online lookups send the searched word to Youdao.")
                .font(.caption).foregroundStyle(Theme.muted).lineSpacing(3)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.rule, lineWidth: 1) }
        .task { await model.load(services.onlineSettings) }
        .alert("Online dictionary settings", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { if let error = model.error { LocalizedMessageText(error) } }
    }
}

#Preview { OnlineDictionarySettingsView(services: .preview()).padding().background(Theme.paper) }
