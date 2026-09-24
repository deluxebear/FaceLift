import SwiftUI

extension ContentView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            ActivityStatusView(vm: vm)
        }
        ToolbarItemGroup(placement: .automatic) {
            pageActions
        }
        ToolbarItemGroup(placement: .primaryAction) {
            primaryActions
            if window.section.hasInspector {
                Button { window.isInspectorPresented.toggle() } label: {
                    Label(L("Inspector"), systemImage: "sidebar.right")
                }
                .help(L("Show/Hide Inspector"))
            }
        }
    }

    @ViewBuilder
    private var pageActions: some View {
        switch window.section {
        case .cards:
            Button { perform(.toggleScanning) } label: {
                Label(vm.isScanningCards ? L("Stop Scanning") : L("Scan Cards"),
                      systemImage: vm.isScanningCards ? "stop.circle" : "wave.3.right")
            }
            .disabled(!vm.canScanCards)
            .help(vm.isScanningCards ? L("Stop Scanning") : L("Scan Cards"))
            Button { perform(.addCardsManually) } label: {
                Label(L("Add Manually"), systemImage: "plus")
            }
            .help(L("Add Manually"))
            Button { perform(.readSelected) } label: {
                Label(L("Read Selected from iPhone"), systemImage: "iphone.and.arrow.forward")
            }
            .disabled(!vm.canReadSelected)
            .help(L("Read artwork for the selected cards only"))
            Button { perform(.setSkinForSelected) } label: {
                Label(L("Set Skin for All..."), systemImage: "photo.on.rectangle.angled")
            }
            .disabled(!vm.canSetSkinForSelected)
            .help(L("Assign one skin to all selected cards"))
        case .passcode:
            Button { perform(.importTheme) } label: {
                Label(L("Choose .passthm File..."), systemImage: "folder.badge.plus")
            }
            .help(L("Choose .passthm File..."))
            targetVersionPicker
        case .creator:
            Button { perform(.choosePoster) } label: {
                Label(vm.creatorPosterImage == nil ? L("Choose Poster...") : L("Change Poster..."), systemImage: "photo")
            }
            .help(vm.creatorPosterImage == nil ? L("Choose Poster...") : L("Change Poster..."))
            Button { perform(.exportTheme) } label: {
                Label(L("Export .passthm..."), systemImage: "square.and.arrow.up")
            }
            .disabled(!vm.canExportCreator)
            .help(L("Export .passthm..."))
            targetVersionPicker
        case .device:
            Button { perform(.refreshDevice) } label: {
                Label(L("Refresh device connection"), systemImage: "arrow.clockwise")
            }
            .disabled(vm.isCheckingDevice)
            .help(L("Refresh device connection"))
        }
    }

    @ViewBuilder
    private var primaryActions: some View {
        switch window.section {
        case .cards:
            Button { perform(.flash) } label: {
                Label(vm.readyToFlashCount > 0 ? L("Flash Skins (%@ Cards)", "\(vm.readyToFlashCount)") : L("Flash Skins"),
                      systemImage: "sparkles")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canFlashCards)
        case .passcode:
            passcodeMoreMenu(clear: .clearTheme, clearTitle: L("Clear Theme"), clearDisabled: vm.loadedPasscodeTheme == nil)
            Button { perform(.flash) } label: {
                Label(L("Flash Passcode Theme"), systemImage: "lock.shield.fill")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canFlashPasscode)
        case .creator:
            passcodeMoreMenu(clear: .clearCreator, clearTitle: L("Clear All"),
                             clearDisabled: vm.effectiveCreatorKeys.isEmpty && vm.creatorPosterImage == nil)
            Button { perform(.flash) } label: {
                Label(L("Flash to iPhone"), systemImage: "lock.shield.fill")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .disabled(!vm.canFlashCreator)
        case .device:
            EmptyView()
        }
    }

    private var targetVersionPicker: some View {
        Picker(L("Target:"), selection: $vm.targetTelephonyVersion) {
            Text(L("TelephonyUI-10 (iOS 18+)")).tag("TelephonyUI-10")
            Text(L("TelephonyUI-9 (iOS 16–17)")).tag("TelephonyUI-9")
            Text(L("TelephonyUI-8 (iOS 14–15)")).tag("TelephonyUI-8")
            Text(L("Universal (All 8, 9, 10)")).tag("all")
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(vm.device?.isUSBConnectedIPhone == true && vm.device?.passcodeCacheVersion != nil)
        .help(L("Target TelephonyUI version"))
    }

    private func passcodeMoreMenu(clear: WindowAction, clearTitle: String, clearDisabled: Bool) -> some View {
        Menu {
            Button(L("Restore Default Passcode...")) { perform(.restoreDefaultPasscode) }
                .disabled(!vm.canRestorePasscode)
            Divider()
            Button(clearTitle, role: .destructive) { perform(clear) }
                .disabled(clearDisabled)
        } label: {
            Label(L("More"), systemImage: "ellipsis.circle")
        }
        .help(L("More"))
    }
}
