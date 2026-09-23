import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = AppViewModel()
    @ObservedObject var language = AppLanguage.shared
    @State var showCredits = false
    @State var showGuide = false
    @State var showRestorePasscodeConfirmation = false
    @State var section: WorkspaceSection = .cards
    @State var cardSearch = ""
    @State var manualHashFeedback = ""
    @State var previewCardIndex = 0
    @State var dragOffsetStart: CGPoint = .zero
    @State var dragKeyStartOffsets: [String: CGPoint] = [:]
    @State var isTargetedPoster = false
    @State var isTargetedTheme = false
    
    var readyToFlashCount: Int {
        vm.cards.filter { $0.isSelected && $0.customImageURL != nil }.count
    }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.90, green: 0.93, blue: 1), Color(red: 0.96, green: 0.98, blue: 1), Color(red: 0.92, green: 0.95, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 218)
                VStack(spacing: 0) {
                    appHeader
                    HStack(spacing: 0) {
                        Group {
                            switch section {
                            case .cards: walletWorkspace
                            case .passcode, .creator: passcodeWorkspace
                            case .device: deviceWorkspace
                            case .settings: settingsWorkspace
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if section == .cards {
                            walletPreview
                                .frame(width: 332)
                                .padding(.trailing, 18)
                                .padding(.bottom, 16)
                        } else if section == .passcode || section == .creator {
                            passcodePreview
                                .frame(width: 332)
                                .padding(.trailing, 18)
                                .padding(.bottom, 16)
                        }
                    }
                    workspaceFooter
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 1120, minHeight: 760)
        .preferredColorScheme(.light)
        .alert("Success!", isPresented: $vm.showSuccessAlert) {
            Button(L("OK")) {}
        } message: {
            if vm.didClearPasscodeCache {
                Text(L("Passcode cache cleared. Restart your iPhone to regenerate the default keypad."))
            } else if vm.selectedTab == .passcodeThemes {
                Text(L("Passcode theme successfully applied!\n\nLock your iPhone to see your new keypad. On iOS 27, restarting may restore the default keypad."))
            } else {
                Text(L("Skins successfully applied to all selected cards!\n\nPlease force-close the Wallet app on your iPhone (or reboot) to see your new designs."))
            }
        }
        .confirmationDialog(L("Restore Default Passcode?"), isPresented: $showRestorePasscodeConfirmation) {
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
        .sheet(isPresented: $showCredits) {
            creditsSheet
        }
        .sheet(isPresented: $showGuide) { guideSheet }
        .sheet(isPresented: $vm.showAddCardSheet) {
            addCardSheet
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

    func navigate(_ destination: WorkspaceSection) {
        section = destination
        switch destination {
        case .cards, .device, .settings: vm.selectedTab = .walletCards
        case .passcode:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .applyTheme
        case .creator:
            vm.selectedTab = .passcodeThemes
            vm.passcodeTabMode = .themeCreator
        }
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 31, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(LinearGradient(colors: [Color(red: 0.28, green: 0.68, blue: 1), FaceLiftPalette.blue], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
                    .shadow(color: FaceLiftPalette.blue.opacity(0.22), radius: 12, y: 6)
                Text("FaceLift")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(FaceLiftPalette.ink)
                Text(L("Make your iPhone yours"))
                    .font(.system(size: 11))
                    .foregroundStyle(FaceLiftPalette.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 44)
            .padding(.bottom, 34)

            VStack(spacing: 6) {
                ForEach(WorkspaceSection.allCases, id: \.self) { item in
                    Button { navigate(item) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 24)
                            Text(item.title)
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .foregroundStyle(section == item ? Color.white : FaceLiftPalette.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(section == item ? FaceLiftPalette.blue : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            Spacer(minLength: 20)
            Button { navigate(.device) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "iphone.gen3")
                        .font(.system(size: 26))
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(vm.device?.connected == true ? (vm.device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(vm.device?.connected == true ? "iOS \(vm.device?.version ?? "") · \(vm.device?.isWiFi == true ? L("Wi-Fi") : L("USB"))" : L("Connect with USB"))
                            .font(.system(size: 10))
                            .foregroundStyle(FaceLiftPalette.muted)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(vm.device?.connected == true ? (vm.device?.isWiFi == true ? Color.orange : Color.green) : Color.gray)
                        .frame(width: 8, height: 8)
                }
                .foregroundStyle(FaceLiftPalette.ink)
                .padding(12)
                .faceLiftWorkspacePanel(cornerRadius: 14, tint: FaceLiftPalette.blue.opacity(0.08))
            }
            .buttonStyle(.plain)
            .padding(13)
        }
        .faceLiftWorkspaceChrome()
        .overlay(alignment: .trailing) { Rectangle().fill(FaceLiftPalette.line.opacity(0.65)).frame(width: 1) }
    }

    var appHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(workspaceTitle)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(FaceLiftPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(workspaceSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(FaceLiftPalette.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button { showGuide = true } label: { Label(L("Guide"), systemImage: "book") }
                .faceLiftSecondaryButton()
            Button { showGuide = true } label: { Label(L("Help"), systemImage: "questionmark.circle") }
                .faceLiftSecondaryButton()
            Menu {
                Button(L("Activity Log")) { vm.showLogs.toggle() }
                Button(L("Credits")) { showCredits = true }
                Button(L("Refresh device connection")) { vm.checkDevice() }
            } label: { Image(systemName: "ellipsis").frame(width: 22) }
                .menuStyle(.borderlessButton)
                .frame(width: 36)
            Button { navigate(.device) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "iphone.gen3")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(vm.device?.connected == true ? (vm.device?.name ?? "iPhone") : L("No iPhone connected"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(vm.device?.connected == true ? "iOS \(vm.device?.version ?? "") · \(vm.device?.isWiFi == true ? L("Wi-Fi") : L("USB"))" : L("Connect with USB"))
                            .font(.system(size: 10))
                            .foregroundStyle(FaceLiftPalette.muted)
                    }
                    Circle().fill(vm.device?.connected == true ? (vm.device?.isWiFi == true ? Color.orange : Color.green) : Color.gray).frame(width: 7, height: 7)
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(FaceLiftPalette.ink)
                .padding(.horizontal, 12)
                .frame(height: 42)
                .faceLiftWorkspacePanel(cornerRadius: 12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FaceLiftPalette.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 25)
        .padding(.trailing, 20)
        .frame(height: 95)
        .faceLiftWorkspaceChrome()
    }

    var workspaceTitle: String {
        switch section {
        case .cards: return L("Personalize your iPhone")
        case .passcode: return L("Personalize Your Lock Screen")
        case .creator: return L("Create a Passcode Theme")
        case .device: return L("Device Connection")
        case .settings: return L("Settings")
        }
    }

    var workspaceSubtitle: String {
        switch section {
        case .cards: return L("Change Wallet artwork and your lock screen keypad.")
        case .passcode: return L("Import, preview and apply a .passthm theme.")
        case .creator: return L("Use a poster or custom images for each key.")
        case .device: return L("Check your iPhone and connection before writing.")
        case .settings: return L("Choose interface language.")
        }
    }
}

extension ContentView {
    var settingsWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Appearance & Language"))
                        .font(.system(size: 17, weight: .bold))
                    HStack {
                        Label(L("Language"), systemImage: "globe")
                        Spacer()
                        Picker("", selection: $language.choice) {
                            Text(L("Follow System")).tag(AppLanguageChoice.system)
                            Text("English").tag(AppLanguageChoice.en)
                            Text("简体中文").tag(AppLanguageChoice.zhHans)
                        }
                        .frame(width: 180)
                    }
                }
                .padding(22)
                .faceLiftWorkspacePanel(cornerRadius: 18)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(FaceLiftPalette.line))
                Button { showCredits = true } label: { Label(L("Credits"), systemImage: "heart") }
                    .faceLiftSecondaryButton()
            }
            .padding(26)
        }
    }
}

extension ContentView {
    var workspaceFooter: some View {
        VStack(spacing: 0) {
            if vm.showLogs { activityLogView.frame(height: 130) }
            Divider()
            HStack(spacing: 12) {
                Circle()
                    .fill(vm.isFlashing ? Color.orange : vm.device?.connected == true ? Color.green : Color.gray)
                    .frame(width: 7, height: 7)
                Text(vm.localizedStatus)
                    .font(.caption)
                    .lineLimit(1)
                if vm.isFlashing {
                    ProgressView(value: vm.progress).frame(width: 130)
                    Text("\(Int(vm.progress * 100))%").font(.caption.monospacedDigit())
                }
                Spacer(minLength: 0)
                Button { withAnimation { vm.showLogs.toggle() } } label: { Label(L("Log"), systemImage: "terminal") }
                    .faceLiftSecondaryButton()
                if section == .cards {
                    Button { vm.applySkin() } label: { Label(readyToFlashCount > 0 ? L("Flash Skins (%@ Cards)", "\(readyToFlashCount)") : L("Flash Skins"), systemImage: "sparkles") }
                        .faceLiftProminentButton()
                        .tint(FaceLiftPalette.blue)
                        .disabled(readyToFlashCount == 0 || vm.isFlashing || vm.isPullingSkins || vm.device?.connected != true)
                } else if section == .passcode {
                    Button { showRestorePasscodeConfirmation = true } label: {
                        Label(L("Restore Default Passcode"), systemImage: "arrow.uturn.backward")
                    }
                        .faceLiftSecondaryButton()
                        .disabled(vm.device?.isUSBConnectedIPhone != true || vm.device?.passcodeCacheVersion == nil || vm.isFlashing || vm.isPullingSkins)
                    Button { vm.flashPasscodeTheme() } label: { Label(L("Flash Passcode Theme"), systemImage: "lock.shield.fill") }
                        .faceLiftProminentButton()
                        .tint(FaceLiftPalette.blue)
                        .disabled(vm.loadedPasscodeTheme == nil || vm.isFlashing || vm.isPullingSkins || vm.device?.isUSBConnectedIPhone != true)
                } else if section == .creator {
                    Button { showRestorePasscodeConfirmation = true } label: {
                        Label(L("Restore Default Passcode"), systemImage: "arrow.uturn.backward")
                    }
                        .faceLiftSecondaryButton()
                        .disabled(vm.device?.isUSBConnectedIPhone != true || vm.device?.passcodeCacheVersion == nil || vm.isFlashing || vm.isPullingSkins)
                    Button { vm.flashCreatedTheme() } label: { Label(L("Flash to iPhone"), systemImage: "lock.shield.fill") }
                        .faceLiftProminentButton()
                        .tint(FaceLiftPalette.blue)
                        .disabled(vm.effectiveCreatorKeys.isEmpty || vm.isFlashing || vm.isPullingSkins || vm.device?.isUSBConnectedIPhone != true)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 55)
        }
        .faceLiftWorkspaceChrome()
    }
}
