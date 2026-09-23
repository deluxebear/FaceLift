import SwiftUI

// MARK: - App Entry Point

@main
struct FaceLiftApp: App {
    @ObservedObject private var language = AppLanguage.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: language.resolved))
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            FaceLiftCommands()
        }

        Settings {
            SettingsView()
                .environment(\.locale, Locale(identifier: language.resolved))
        }
    }
}
