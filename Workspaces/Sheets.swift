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

/// The artwork saved for one card: the original captured before FaceLift
/// first changed it, then every design FaceLift has written, newest first.
struct ArtworkHistorySheet: View {
    @ObservedObject var vm: AppViewModel
    let target: ArtworkHistoryTarget
    let onRestoreOriginal: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let original = DeviceProfileStore.originalManifest(udid: target.udid, cardId: target.cardId)
        let originalPreview = DeviceProfileStore.originalPreviewURL(udid: target.udid, cardId: target.cardId)
        let items = DeviceProfileStore.history(udid: target.udid, cardId: target.cardId)
        let current = Self.currentID(
            DeviceProfileStore.currentArtwork(udid: target.udid, cardId: target.cardId),
            items: items,
            hasOriginal: original != nil
        )
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Artwork History"))
                .font(.headline)
            Text(target.cardId)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if original == nil && items.isEmpty {
                ContentUnavailableView(
                    L("Nothing Saved Yet"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(L("Reading this card or flashing it saves its original artwork first."))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], alignment: .leading, spacing: 16) {
                        if let original {
                            tile(url: originalPreview, title: L("Original"), subtitle: Self.displayDate(original.capturedAt)) {
                                if current == Self.originalID {
                                    currentBadge
                                } else {
                                    Button(L("Restore…")) {
                                        dismiss()
                                        DispatchQueue.main.async { onRestoreOriginal() }
                                    }
                                    .disabled(!vm.canRestoreOriginal)
                                }
                            }
                        }
                        ForEach(items) { item in
                            tile(url: item.url, title: L("Written by FaceLift"), subtitle: Self.displayDate(item.appliedAt)) {
                                if current == item.id {
                                    currentBadge
                                } else {
                                    Button(L("Use This Design")) {
                                        vm.useHistoryArtwork(item.url, for: target.cardId)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                if original?.suspectModified == true {
                    NoticeBar(title: L("This card may already have been changed before its original was saved, so the saved original may not be the issuer's design.")) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            HStack {
                Spacer()
                Button(L("Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private func tile<Action: View>(url: URL?, title: String, subtitle: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(1.59, contentMode: .fit)
                .overlay {
                    if let url, let image = NSImage(contentsOf: url) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
            Text(title)
                .font(.callout.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            action()
                .controlSize(.small)
        }
    }

    private static let originalID = "original"

    /// Which tile FaceLift last wrote to the iPhone. Cards written before
    /// this was recorded fall back to the newest write, else the original.
    private static func currentID(_ current: CurrentArtwork?, items: [ArtworkHistoryItem], hasOriginal: Bool) -> String? {
        if let current {
            if current.isOriginal { return hasOriginal ? originalID : nil }
            return items.first(where: { $0.sha256 != nil && $0.sha256 == current.sha256 })?.id
        }
        return items.first?.id ?? (hasOriginal ? originalID : nil)
    }

    private var currentBadge: some View {
        Label(L("Current Artwork"), systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.brand)
            .help(L("The artwork FaceLift last wrote to this iPhone. Changes made outside FaceLift are not detected."))
    }

    private static func displayDate(_ iso: String?) -> String {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
