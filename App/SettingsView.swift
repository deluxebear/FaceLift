import SwiftUI

/// ⌘, Settings window.
struct SettingsView: View {
    @AppStorage(AppAppearanceChoice.storageKey) private var appearance: AppAppearanceChoice = .system
    @ObservedObject private var language = AppLanguage.shared

    var body: some View {
        Form {
            Section(L("General")) {
                Picker(L("Appearance"), selection: $appearance) {
                    Text(L("Follow System")).tag(AppAppearanceChoice.system)
                    Text(L("Light")).tag(AppAppearanceChoice.light)
                    Text(L("Dark")).tag(AppAppearanceChoice.dark)
                }
                Picker(L("Language"), selection: $language.choice) {
                    Text(L("Follow System")).tag(AppLanguageChoice.system)
                    Text("English").tag(AppLanguageChoice.en)
                    Text("简体中文").tag(AppLanguageChoice.zhHans)
                }
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme(appearance.colorScheme)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
