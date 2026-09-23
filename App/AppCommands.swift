import SwiftUI

/// Menu bar commands. They act on the focused window through the
/// `WindowState` and `AppViewModel` it publishes with `focusedSceneObject`,
/// and share enablement with the toolbar via `AppViewModel`'s `can…` checks.
struct FaceLiftCommands: Commands {
    @FocusedObject private var vm: AppViewModel?
    @FocusedObject private var window: WindowState?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About FaceLift")) { window?.showCredits = true }
                .disabled(window == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Import .passthm...")) { window?.send(.importTheme) }
                .keyboardShortcut("o")
                .disabled(window == nil)
            Button(L("Choose Poster...")) { window?.send(.choosePoster) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(window?.section != .creator)
            Button(L("Set Skin for Selected Cards...")) { window?.send(.setSkinForSelected) }
                .disabled(window?.section != .cards || vm?.canSetSkinForSelected != true)
        }

        CommandGroup(before: .sidebar) {
            ForEach(WorkspaceSection.allCases, id: \.self) { item in
                Button(item.title) { window?.section = item }
                    .keyboardShortcut(item.shortcut)
                    .disabled(window == nil)
            }
            Divider()
        }

        CommandGroup(after: .sidebar) {
            Button(L("Show/Hide Inspector")) { window?.isInspectorPresented.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(window?.section.hasInspector != true)
            Button(L("Show Activity Log")) { vm?.showLogs.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(vm == nil)
        }

        CommandMenu(L("Device")) {
            Button(L("Refresh device connection")) { window?.send(.refreshDevice) }
                .keyboardShortcut("r")
                .disabled(vm == nil || vm?.isCheckingDevice == true)
            Button(vm?.isScanningCards == true ? L("Stop Scanning") : L("Scan Cards")) {
                window?.section = .cards
                window?.send(.toggleScanning)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(vm?.canScanCards != true)
            Divider()
            Button(L("Flash to iPhone")) { window?.send(.flash) }
                .keyboardShortcut(.return)
                .disabled(window.map { vm?.canFlash(in: $0.section) == true } != true)
            Button(L("Restore Default Passcode...")) { window?.send(.restoreDefaultPasscode) }
                .disabled(vm?.canRestorePasscode != true)
        }

        CommandGroup(replacing: .help) {
            Button(L("FaceLift Guide")) { window?.showGuide = true }
                .keyboardShortcut("?", modifiers: .command)
                .disabled(window == nil)
        }
    }
}
