import SwiftUI
import FolioCore

struct LanguageSettingsView: View {
    @Bindable var manager: AppLanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Language").font(Theme.headword).accessibilityAddTraits(.isHeader)
            Picker("App language", selection: $manager.selection) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(LocalizedStringKey(language.title)).tag(language)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(minHeight: 44)
            Text("Choose the language that feels like home. Changes appear immediately.")
                .font(.subheadline).foregroundStyle(Theme.muted).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.rule, lineWidth: 1) }
    }
}

#Preview("English") {
    LanguageSettingsView(manager: AppLanguageManager(defaults: nil, initial: .english))
        .padding().background(Theme.paper)
}
#Preview("简体中文 · Narrow") {
    LanguageSettingsView(manager: AppLanguageManager(defaults: nil, initial: .simplifiedChinese))
        .environment(\.locale, Locale(identifier: "zh-Hans")).frame(width: 320).padding(.vertical).background(Theme.paper)
}
