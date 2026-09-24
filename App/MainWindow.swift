import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = AppViewModel()
    @StateObject var window = WindowState()
    @ObservedObject var language = AppLanguage.shared
    @State var cardSearch = ""
    @State var manualHashFeedback = ""
    @State var previewCardIndex = 0
    @State var dragOffsetStart: CGPoint = .zero
    @State var dragKeyStartOffsets: [String: CGPoint] = [:]
    @State var isTargetedPoster = false
    @State var isTargetedTheme = false

    // Forwarders so workspace code keeps reading and writing window state
    // by its original names.
    var section: WorkspaceSection {
        get { window.section }
        nonmutating set { window.section = newValue }
    }
    var showGuide: Bool {
        get { window.showGuide }
        nonmutating set { window.showGuide = newValue }
    }
    var showCredits: Bool {
        get { window.showCredits }
        nonmutating set { window.showCredits = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            windowLayout(width: geometry.size.width)
        }
        .frame(minWidth: 900, minHeight: 600)
        .tint(Color.brand)
        .focusedSceneObject(vm)
        .focusedSceneObject(window)
        .alert(successTitle, isPresented: $vm.showSuccessAlert) {
            Button(L("OK")) {}
        } message: {
            Text(successMessage)
        }
        .confirmationDialog(L("Restore Default Passcode?"), isPresented: $window.showRestorePasscodeConfirmation) {
            Button(L("Restore Default Passcode"), role: .destructive) { vm.restoreDefaultPasscode() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("This backs up and removes the passcode keypad cache for this iOS version. Restart the iPhone afterward so iOS can rebuild its default keypad."))
        }
        .alert(L("Error"), isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button(L("OK")) { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
        .sheet(isPresented: $window.showCredits) { creditsSheet }
        .sheet(isPresented: $window.showGuide) { guideSheet }
        .sheet(isPresented: $vm.showAddCardSheet) { addCardSheet }
        .onChange(of: window.section) { _, destination in syncViewModel(to: destination) }
        .onChange(of: vm.passcodeTabMode) { _, mode in
            // Programmatic mode changes (e.g. "Edit in Creator") move the sidebar too.
            guard window.section == .passcode || window.section == .creator else { return }
            window.section = mode == .applyTheme ? .passcode : .creator
        }
        .onChange(of: window.pendingAction) { _, action in
            guard let action else { return }
            window.pendingAction = nil
            // Defer so a page switch renders before any modal open panel appears.
            DispatchQueue.main.async { perform(action) }
        }
        .onChange(of: vm.selectedTab) { _, newTab in
            if newTab == .passcodeThemes && vm.isScanningCards {
                vm.stopCardScanning()
            }
            vm.dismissScanPrompt()
        }
        .onChange(of: vm.cards.count) { _, count in
            if count == 0 || previewCardIndex >= count { previewCardIndex = 0 }
        }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            if !vm.isFlashing && !vm.isScanningCards && !vm.isPullingSkins {
                vm.checkDevice(silent: true)
            }
        }
    }

    private func windowLayout(width: CGFloat) -> some View {
        // Keep every preview the same width while leaving room for three minimum-size cards.
        let threeColumnWorkspaceWidth: CGFloat = 3 * 210 + 2 * 13 + 2 * 25
        let preferredSidebarWidth: CGFloat = 210
        let inspectorWidth = min(400, max(280, width - preferredSidebarWidth - threeColumnWorkspaceWidth))

        return NavigationSplitView {
            SidebarView(vm: vm, selection: $window.section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(window.section.title)
                .navigationSubtitle(window.section.subtitle)
                .toolbar { toolbarContent }
                .inspector(isPresented: $window.isInspectorPresented) {
                    inspectorContent
                        .inspectorColumnWidth(min: inspectorWidth, ideal: inspectorWidth, max: inspectorWidth)
                }
        }
        // Keep the window toolbar on one surface during the inspector's first render.
        .toolbarBackground(Color(nsColor: .textBackgroundColor), for: .windowToolbar)
    }

    @ViewBuilder
    private var detail: some View {
        switch window.section {
        case .cards: walletWorkspace
        case .passcode, .creator: passcodeWorkspace
        case .device: deviceWorkspace
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch window.section {
        case .cards: walletPreview
        case .passcode, .creator: passcodePreview
        case .device: EmptyView()
        }
    }

    private var lastFlashWasPasscode: Bool {
        window.lastFlashSection == .passcode || window.lastFlashSection == .creator
    }

    private var successTitle: String {
        if vm.didClearPasscodeCache { return L("Passcode Cache Cleared") }
        return lastFlashWasPasscode ? L("Passcode Theme Written") : L("Skins Flashed")
    }

    private var successMessage: String {
        if vm.didClearPasscodeCache {
            return L("Passcode cache cleared. Restart your iPhone to regenerate the default keypad.")
        } else if lastFlashWasPasscode {
            return L("Passcode theme successfully applied!\n\nLock your iPhone to see your new keypad. On iOS 27, restarting may restore the default keypad.")
        }
        return L("Skins successfully applied to all selected cards!\n\nPlease force-close the Wallet app on your iPhone (or reboot) to see your new designs.")
    }

    func navigate(_ destination: WorkspaceSection) {
        window.section = destination
    }

    /// Keeps the view model's tab/mode in step with the sidebar selection.
    private func syncViewModel(to destination: WorkspaceSection) {
        switch destination {
        case .cards, .device:
            vm.selectedTab = .walletCards
        case .passcode:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .applyTheme
        case .creator:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .themeCreator
        }
    }

    func perform(_ action: WindowAction) {
        switch action {
        case .importTheme:
            navigate(.passcode)
            openPasscodeThemePicker()
        case .choosePoster:
            navigate(.creator)
            openPosterPicker()
        case .setSkinForSelected:
            openBulkImagePicker()
        case .flash:
            // Menu/toolbar enablement can lag a run-loop turn behind isFlashing.
            guard vm.canFlash(in: window.section) else { return }
            window.lastFlashSection = window.section
            switch window.section {
            case .cards: vm.applySkin()
            case .passcode: vm.flashPasscodeTheme()
            case .creator: vm.flashCreatedTheme()
            case .device: break
            }
        case .restoreDefaultPasscode:
            window.showRestorePasscodeConfirmation = true
        case .refreshDevice:
            vm.checkDevice()
        case .toggleScanning:
            vm.toggleCardScanning()
        case .readSelected:
            vm.queueSkinPulls(ids: vm.cards.filter(\.isSelected).map(\.id), replacingStored: true)
        case .addCardsManually:
            vm.showAddCardSheet = true
        case .clearTheme:
            vm.loadedPasscodeTheme = nil
        case .clearCreator:
            vm.clearCreator()
        }
    }
}
