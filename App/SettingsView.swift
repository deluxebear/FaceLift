import SwiftUI

/// ⌘, Settings window.
struct SettingsView: View {
    @ObservedObject private var language = AppLanguage.shared

    var body: some View {
        Form {
            Section(L("General")) {
                Picker(L("Language"), selection: $language.choice) {
                    Text(L("Follow System")).tag(AppLanguageChoice.system)
                    Text("English").tag(AppLanguageChoice.en)
                    Text("简体中文").tag(AppLanguageChoice.zhHans)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
