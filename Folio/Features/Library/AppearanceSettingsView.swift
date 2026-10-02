import SwiftUI

struct AppearanceSettingsView: View {
    @Bindable var manager: AppAppearanceManager
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Appearance").font(Theme.headword).accessibilityAddTraits(.isHeader)
            Picker("Appearance", selection: $manager.selection) {
                ForEach(AppAppearance.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
            }.pickerStyle(.menu).labelsHidden().frame(minHeight: 44)
            Text("Follow your device, or choose a quieter light for reading.")
                .font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(Theme.rule, lineWidth: 1) }
    }
}

#Preview { AppearanceSettingsView(manager: .init(defaults: nil)).padding().background(Theme.paper) }
#Preview("Dark") { AppearanceSettingsView(manager: .init(defaults: nil, initial: .dark)).padding().background(Theme.paper).preferredColorScheme(.dark) }
