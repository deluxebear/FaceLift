import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            Text(text)
        }
    }
}

extension ContentView {
    var guideSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("FaceLift Guide"))
                .font(.headline)
            guideGroup(L("Cards"), steps: [
                L("Connect iPhone to your Mac with USB."),
                L("Scan Wallet cards, or add a card hash manually."),
                L("Choose artwork, select cards, then write the skins."),
            ])
            guideGroup(L("Lock Screen Themes"), steps: [
                L("Import a passcode theme or create one from images."),
                L("Review the preview and write the theme to iPhone."),
            ])
            HStack {
                Spacer()
                Button(L("Done")) { showGuide = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func guideGroup(_ title: String, steps: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { offset, step in
                instructionRow("\(offset + 1)", step)
            }
        }
    }
}

extension ContentView {
    var creditsSheet: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text("FaceLift")
                    .font(.title3.weight(.semibold))
                Text(L("Version %@", appVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(L("Apple Wallet Skins & Passcode Themes for iOS 18+"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                creditRow(L("Developer & Maintainer:")) {
                    Link("@deluxebear", destination: URL(string: "https://github.com/deluxebear")!)
                }
                creditRow(L("AirCard Author:")) {
                    HStack(spacing: 4) {
                        Link("@mak5er", destination: URL(string: "https://github.com/mak5er")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Twitter / X", destination: URL(string: "https://x.com/mak5er")!)
                    }
                }
                creditRow(L("AirCard Contributor:")) {
                    HStack(spacing: 4) {
                        Link("@Lumid-Off", destination: URL(string: "https://github.com/Lumid-Off")!)
                        Text("·").foregroundStyle(.secondary)
                        Link("Twitter / X", destination: URL(string: "https://x.com/LumidOff")!)
                    }
                }
                creditRow(L("Based on:")) {
                    HStack(spacing: 4) {
                        Link("AirCard v1.2.3", destination: URL(string: "https://github.com/mak5er/AirCard")!)
                        Text(L("(MIT License)")).foregroundStyle(.secondary)
                    }
                }
                creditRow(L("Core Exploit:")) {
                    Text(L("airlift (AirTraffic sync escape)"))
                }
                creditRow(L("Passcode Themes:")) {
                    Text(L(".passthm standard (Cowabunga / Nugget)"))
                }
            }
            .font(.callout)
            HStack {
                Spacer()
                Button(L("Done")) { showCredits = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func creditRow<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            value()
                .gridColumnAlignment(.leading)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var addCardSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Add Card Hashes Manually"))
                .font(.headline)
            Text(L("Paste one or more card hashes (separated by spaces, commas, or newlines):"))
                .font(.callout)
                .foregroundStyle(.secondary)
            TextEditor(text: $vm.manualHashInput)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            Text(L("Use a hash previously scanned by FaceLift or saved in a card backup. Adding a hash only saves it to this list; it does not create or verify a card on your iPhone."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !manualHashFeedback.isEmpty {
                Text(manualHashFeedback)
                    .font(.caption)
                    .foregroundStyle(Color.brand)
            }
            HStack {
                Spacer()
                Button(L("Cancel")) {
                    vm.showAddCardSheet = false
                    vm.manualHashInput = ""
                    manualHashFeedback = ""
                }
                .keyboardShortcut(.cancelAction)
                Button(L("Add to List")) {
                    let result = vm.addCardHash(vm.manualHashInput)
                    if result.rejected.isEmpty {
                        vm.showAddCardSheet = false
                        vm.manualHashInput = ""
                        manualHashFeedback = ""
                    } else {
                        vm.manualHashInput = result.rejected.joined(separator: "\n")
                        manualHashFeedback = result.added > 0
                            ? L("Added %@ card hash(es). Invalid or duplicate entries remain below.", "\(result.added)")
                            : L("No card hashes were added. Check the format or remove duplicates.")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(vm.manualHashInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
