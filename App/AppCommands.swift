import SwiftUI

/// Menu bar commands. They act on the focused window through the
/// `WindowState` and `AppViewModel` it publishes with `focusedSceneObject`,
/// and share enablement with the toolbar via `AppViewModel`'s `can…` checks.
struct FaceLiftCommands: Commands {
    @FocusedObject private var vm: AppViewModel?
    @FocusedObject private var window: WindowState?

    /// Window- or view-model-owned sheets and alerts; commands that act on
    /// the window stay disabled while one is up.
    private var isBlocked: Bool {
        window == nil
            || window?.isPresentingModal == true
            || vm?.showAddCardSheet == true
            || vm?.showSuccessAlert == true
            || vm?.errorMessage != nil
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(L("About FaceLift")) { window?.showCredits = true }
                .disabled(window == nil)
        }

        CommandGroup(replacing: .newItem) {
            Button(L("Import .passthm...")) { window?.send(.importTheme) }
                .keyboardShortcut("o")
                .disabled(isBlocked)
            Button(L("Choose Poster...")) { window?.send(.choosePoster) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(isBlocked || window?.section != .creator)
            Button(L("Set Skin for Selected Cards...")) { window?.send(.setSkinForSelected) }
                .disabled(isBlocked || window?.section != .cards || vm?.canSetSkinForSelected != true)
        }

        CommandGroup(before: .sidebar) {
            ForEach(WorkspaceSection.allCases, id: \.self) { item in
                Button(item.title) { window?.section = item }
                    .keyboardShortcut(item.shortcut)
                    .disabled(isBlocked)
            }
            Divider()
        }

        CommandGroup(after: .sidebar) {
            Button(window?.isInspectorPresented == true ? L("Hide Inspector") : L("Show Inspector")) { window?.isInspectorPresented.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(isBlocked || window?.section.hasInspector != true)
            Button(vm?.showLogs == true ? L("Hide Activity Log") : L("Show Activity Log")) { vm?.showLogs.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(isBlocked || vm == nil)
        }

        CommandMenu(L("Device")) {
            Button(L("Refresh device connection")) { window?.send(.refreshDevice) }
                .keyboardShortcut("r")
                .disabled(isBlocked || vm == nil || vm?.isCheckingDevice == true)
            Button(vm?.isScanningCards == true ? L("Stop Scanning") : L("Scan Cards")) {
                window?.section = .cards
                window?.send(.toggleScanning)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(isBlocked || vm?.canScanCards != true)
            Divider()
            Button(L("Flash to iPhone")) { window?.send(.flash) }
                .keyboardShortcut(.return)
                .disabled(isBlocked || window.map { vm?.canFlash(in: $0.section) == true } != true)
            Button(L("Restore Default Passcode...")) { window?.send(.restoreDefaultPasscode) }
                .disabled(isBlocked || vm?.canRestorePasscode != true)
        }

        CommandGroup(replacing: .help) {
            Button(L("FaceLift Guide")) { window?.showGuide = true }
                .keyboardShortcut("?", modifiers: .command)
                .disabled(window == nil)
        }
    }
}
