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
}
