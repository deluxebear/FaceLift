import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var applyThemeInspector: some View {
        Form {
            Section(L("Passcode Theme File")) {
                if let theme = vm.loadedPasscodeTheme {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.square.stack.fill")
                            .font(.title)
                            .foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name)
                                .font(.headline)
                                .lineLimit(2)
                            Text(theme.supportedVersions.count > 1
                                 ? L("Supports %@", theme.supportedVersions.joined(separator: ", "))
                                 : theme.detectedVersion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L("%@ artwork assets", "\(theme.fileCount)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button { vm.editLoadedThemeInCreator() } label: {
                        Label(L("Edit in Creator"), systemImage: "pencil.and.outline")
                    }
                } else {
                    LabeledContent {
                        Button(L("Choose File...")) { openPasscodeThemePicker() }
                    } label: {
                        Text(L("No theme selected"))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            flashTargetSection
        }
        .formStyle(.grouped)
    }

    /// Language and weight targets shared by the Lock Screen and Creator inspectors.
    var flashTargetSection: some View {
        let isUniversal = vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both
        return Section {
            Picker(L("Keyboard Language"), selection: $vm.passcodeLanguageTarget) {
                ForEach(PasscodeLanguageTarget.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            Picker(L("Font Weight"), selection: $vm.passcodeBoldTarget) {
                ForEach(PasscodeBoldTarget.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
        } header: {
            Text(L("Flash Target"))
        } footer: {
            Text(isUniversal
                 ? L("Universal mode flashes ~600 files for all languages & Bold text. Selecting a specific language (e.g. Ukrainian) speeds up flashing dramatically.")
                 : L("Fast mode selected: only targets %@ with %@.", vm.passcodeLanguageTarget.title, vm.passcodeBoldTarget.title))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
