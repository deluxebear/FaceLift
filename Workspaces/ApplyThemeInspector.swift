import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    // MARK: - Apply Theme Mode
    
    var passcodeApplyThemeWorkspaceView: some View {
        VStack(alignment: .leading, spacing: 14) {
            applyThemeControlsCard
            targetSettingsCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDrop(of: [UTType.fileURL, UTType.data], isTargeted: nil) { providers in
            if let provider = providers.first {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        Task { @MainActor in
                            vm.inspectPasscodeTheme(url: url)
                        }
                    } else if let url = item as? URL {
                        Task { @MainActor in
                            vm.inspectPasscodeTheme(url: url)
                        }
                    }
                }
                return true
            }
            return false
        }
    }
    
    var applyThemeControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Passcode Theme File"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            if let theme = vm.loadedPasscodeTheme {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.square.stack.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color.brand)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name)
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text(theme.supportedVersions.count > 1
                                 ? L("Supports %@", theme.supportedVersions.joined(separator: ", "))
                                 : theme.detectedVersion)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brand.opacity(0.15))
                                .foregroundColor(Color.brand)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(L("%@ artwork assets loaded · Ready to flash to iPhone", "\(theme.fileCount)"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Button(action: { vm.editLoadedThemeInCreator() }) {
                            Label(L("Edit in Creator"), systemImage: "pencil.and.outline")
                        }
                        .faceLiftProminentButton()
                        .tint(Color.brand)
                        .controlSize(.regular)
                        
                        Button(L("Change...")) {
                            openPasscodeThemePicker()
                        }
                        .faceLiftSecondaryButton()
                        .controlSize(.regular)
                        
                        Button(L("Clear")) {
                            vm.loadedPasscodeTheme = nil
                        }
                        .faceLiftSecondaryButton()
                        .controlSize(.regular)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .faceLiftPanel(cornerRadius: 12, fallback: Color(NSColor.controlBackgroundColor))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color.brand)
                    
                    Text(L("Drop .passthm file here"))
                        .font(.caption)
                        .fontWeight(.semibold)
                    
                    Text(L("Supports .passthm, .passtheme, or .zip packages from Cowabunga or Nugget"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                    
                    Button(L("Choose File...")) {
                        openPasscodeThemePicker()
                    }
                    .faceLiftProminentButton()
                    .tint(Color.brand)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isTargetedTheme ? Color.brand : Color.brand.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .background(faceLiftDropZoneFill(cornerRadius: 12))
                )
                .onDrop(of: [UTType.fileURL, UTType.data], isTargeted: $isTargetedTheme) { providers in
                    if let provider = providers.first {
                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                Task { @MainActor in
                                    vm.inspectPasscodeTheme(url: url)
                                }
                            } else if let url = item as? URL {
                                Task { @MainActor in
                                    vm.inspectPasscodeTheme(url: url)
                                }
                            }
                        }
                        return true
                    }
                    return false
                }
            }
        }
        .padding(14)
        .faceLiftPanel(cornerRadius: 14, fallback: Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Passcode Target Configuration Box
    
    var targetSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(Color.brand)
                    .font(.body.weight(.semibold))
                Text(L("Flash & Language Target"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // 1. Language Target Selector
            VStack(alignment: .leading, spacing: 4) {
                Text(L("System Language:"))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $vm.passcodeLanguageTarget) {
                    ForEach(PasscodeLanguageTarget.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            
            // 2. Bold / Font Weight Selector
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Font Weight / Style:"))
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $vm.passcodeBoldTarget) {
                    ForEach(PasscodeBoldTarget.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            
            // Helpful Speed / Info Hint
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both ? "globe" : "bolt.fill")
                    .font(.caption)
                    .foregroundColor(vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both ? .secondary : .orange)
                    .padding(.top, 1)
                
                if vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both {
                    Text(L("Universal mode flashes ~600 files for all languages & Bold text. Selecting a specific language (e.g. Ukrainian) speeds up flashing dramatically."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Fast mode selected: only targets %@ with %@.", vm.passcodeLanguageTarget.title, vm.passcodeBoldTarget.title))
                        .font(.caption)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .faceLiftPanel(cornerRadius: 10, fallback: Color(NSColor.controlBackgroundColor).opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.brand.opacity(0.3), lineWidth: 1))
    }
}
