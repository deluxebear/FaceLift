import SwiftUI

/// Single source of truth for whether an action is available. Toolbar
/// buttons and menu commands both read these, so they never disagree.
extension AppViewModel {
    var isBusy: Bool { isFlashing || isPullingSkins }
    var isConnected: Bool { device?.connected == true }
    var readyToFlashCount: Int { cards.filter { $0.isSelected && $0.customImageURL != nil }.count }
    var hasSelectedCards: Bool { cards.contains(where: \.isSelected) }

    // Device actions also need the connected iPhone to be the one whose
    // cards are shown, so nothing is written with another iPhone's data.
    var canScanCards: Bool { isActiveDeviceConnected }
    var canReadSelected: Bool { isActiveDeviceConnected && device?.isWiFi != true && !isBusy && hasSelectedCards }
    var canSetSkinForSelected: Bool { hasSelectedCards }
    var canFlashCards: Bool { readyToFlashCount > 0 && !isBusy && isActiveDeviceConnected }
    var canFlashPasscode: Bool {
        loadedPasscodeTheme != nil && !isBusy && device?.isUSBConnectedIPhone == true && isActiveDeviceConnected
    }
    var canFlashCreator: Bool {
        !effectiveCreatorKeys.isEmpty && !isBusy && device?.isUSBConnectedIPhone == true && isActiveDeviceConnected
    }
    var canExportCreator: Bool { !effectiveCreatorKeys.isEmpty }
    var canRestorePasscode: Bool {
        device?.isUSBConnectedIPhone == true && device?.passcodeCacheVersion != nil && !isBusy && isActiveDeviceConnected
    }

    func canFlash(in section: WorkspaceSection) -> Bool {
        switch section {
        case .cards: return canFlashCards
        case .passcode: return canFlashPasscode
        case .creator: return canFlashCreator
        case .device: return false
        }
    }
}
