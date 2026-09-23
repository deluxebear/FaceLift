import SwiftUI

/// Commands that the menu bar and toolbar ask the main window to perform.
/// Actions that need an open panel or window-local state are routed through
/// `WindowState.send(_:)` and handled by `ContentView.perform(_:)`.
enum WindowAction: Equatable {
    case importTheme
    case choosePoster
    case setSkinForSelected
    case flash
    case restoreDefaultPasscode
    case refreshDevice
    case toggleScanning
    case readSelected
    case addCardsManually
    case clearTheme
    case clearCreator
}

/// Window-level UI state shared between the main window and menu commands
/// (published with `focusedSceneObject`).
@MainActor
final class WindowState: ObservableObject {
    @Published var section: WorkspaceSection = .cards
    @Published var inspectorHidden: Set<WorkspaceSection> = []
    @Published var showGuide = false
    @Published var showCredits = false
    @Published var showRestorePasscodeConfirmation = false
    @Published var pendingAction: WindowAction?
    /// Page whose content was last sent to the iPhone; picks the success alert text.
    @Published var lastFlashSection: WorkspaceSection?

    /// Inspector visibility, remembered separately for each page.
    var isInspectorPresented: Bool {
        get { section.hasInspector && !inspectorHidden.contains(section) }
        set {
            if newValue { inspectorHidden.remove(section) } else { inspectorHidden.insert(section) }
        }
    }

    /// True while a sheet or confirmation owned by the window is showing.
    var isPresentingModal: Bool { showGuide || showCredits || showRestorePasscodeConfirmation }

    func send(_ action: WindowAction) { pendingAction = action }
}
