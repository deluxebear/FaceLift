import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct FaceLiftApp: App {
    @ObservedObject private var language = AppLanguage.shared

    init() {
        // The app navigates through its sidebar; macOS window tabs add a
        // redundant row above every workspace.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

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
