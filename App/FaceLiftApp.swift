import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - App Entry Point

@main
struct FaceLiftApp: App {
    @ObservedObject private var language = AppLanguage.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: language.resolved))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu(L("Language")) {
                Picker(selection: $language.choice) {
                    Text(L("Follow System")).tag(AppLanguageChoice.system)
                    Text("English").tag(AppLanguageChoice.en)
                    Text("简体中文").tag(AppLanguageChoice.zhHans)
                } label: {
                    Text(L("Language"))
                }
            }
        }
    }
}
