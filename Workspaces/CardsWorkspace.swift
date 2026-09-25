import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct CardSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusRequest: Int

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let text: Binding<String>
        var handledFocusRequest = 0

        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

struct WalletTileView: View {
    @Binding var card: CardItem
    let index: Int
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let onDelete: () -> Void
    let onStoreImage: (URL) -> Void
    let onShowHistory: () -> Void
    let onRestoreOriginal: () -> Void
    let hasOriginal: Bool
    let canRestoreOriginal: Bool
    @State private var isTargeted = false

    private let artworkShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
            HStack(alignment: .top, spacing: 6) {
                Toggle(isOn: $card.isSelected) { EmptyView() }
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .help(card.isSelected ? L("Remove from flash") : L("Include in flash"))
                    .accessibilityLabel(Text(L("Card #%@", String(index + 1))))
                    .accessibilityValue(Text(card.isSelected ? L("Selected for flash") : L("Not selected for flash")))
                    .accessibilityHint(Text(card.isSelected ? L("Remove from flash") : L("Include in flash")))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Card #%@", String(index + 1)))
                        .font(.headline)
                    Text(card.customImage == nil ? L("Artwork not set") : L("Artwork ready"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Menu { menuItems } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L("More"))
            }
            .padding(.horizontal, 3)
        }
        .contextMenu { menuItems }
    }

    private var artwork: some View {
        ZStack {
            if let image = card.customImage {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
            } else {
                artworkPlaceholder
            }
        }
        .aspectRatio(1.59, contentMode: .fit)
        .clipShape(artworkShape)
        .overlay(artworkShape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .overlay(alignment: .topTrailing) {
            if card.isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.brand)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .padding(3) // Room for the selection ring.
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.brand, lineWidth: 3)
                .opacity(card.isSelected || isTargeted ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPickImage)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                guard let url, NSImage(contentsOf: url) != nil else { return }
                Task { @MainActor in onStoreImage(url) }
            }
            return true
        }
    }

    private var artworkPlaceholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            VStack(spacing: 6) {
                Image(systemName: "photo.badge.plus")
                    .font(.title2)
                Text(L("Add Artwork"))
                    .font(.callout.weight(.medium))
                Text(card.id.prefix(8) + "…" + card.id.suffix(6))
                    .font(.caption.monospaced())
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button(L("Change Skin"), action: onPickImage)
        if card.customImage != nil { Button(L("Remove skin"), action: onClearImage) }
        Button(L("Copy full hash")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(card.id, forType: .string)
        }
        Divider()
        Button(L("Artwork History…"), action: onShowHistory)
        Button(L("Restore Original Artwork…"), action: onRestoreOriginal)
            .disabled(!hasOriginal || !canRestoreOriginal)
        Divider()
        Button(L("Remove from list"), role: .destructive, action: onDelete)
    }
}

extension ContentView {
    var walletWorkspace: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(cardCountSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    CardSearchField(
                        text: $cardSearch,
                        placeholder: L("Search cards by hash or number"),
                        focusRequest: window.cardSearchFocusRequest
                    )
                    .frame(minWidth: 150, idealWidth: 240, maxWidth: 280)
                    .accessibilityLabel(Text(L("Search cards by hash or number")))
                    Menu {
                        Button(L("Select All")) { for i in vm.cards.indices { vm.cards[i].isSelected = true } }
                            .disabled(vm.cards.isEmpty)
                        Button(L("Deselect All")) { for i in vm.cards.indices { vm.cards[i].isSelected = false } }
                            .disabled(vm.cards.isEmpty)
                        if vm.legacyCardCount > 0 && vm.activeProfileUDID != nil {
                            Divider()
                            Button(L("Add Cards Saved by an Earlier Version")) { vm.importLegacyCards() }
                        }
                        Divider()
                        Button(L("Clear All"), role: .destructive) { vm.clearAllCards() }
                            .disabled(vm.cards.isEmpty)
                    } label: {
                        Label(L("Selection"), systemImage: "checklist")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(vm.cards.isEmpty && vm.legacyCardCount == 0)
                }
                if let notice = vm.profileNotice {
                    NoticeBar(title: notice) {
                        Image(systemName: "iphone.slash")
                            .foregroundStyle(.secondary)
                    }
                }
                if vm.isScanningCards { scanningNoticeBanner }
                if hiddenReadyToFlashCount > 0 {
                    NoticeBar(title: L("Search hides %@ selected card(s) ready to flash. Flashing still includes them.", "\(hiddenReadyToFlashCount)")) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()

            if vm.cards.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        if filteredCardIndices.isEmpty {
                            ContentUnavailableView.search(text: cardSearch)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: walletGridColumns(for: geometry.size.width), spacing: 16) {
                                ForEach(filteredCardIndices, id: \.self) { index in
                                    WalletTileView(
                                        card: $vm.cards[index], index: index,
                                        onPickImage: { openCardImagePicker(for: vm.cards[index].id) },
                                        onClearImage: { vm.clearCardImage(for: vm.cards[index].id) },
                                        onDelete: { vm.deleteCard(id: vm.cards[index].id) },
                                        onStoreImage: { vm.storeSkin(for: vm.cards[index].id, url: $0) },
                                        onShowHistory: { vm.showArtworkHistory(for: vm.cards[index].id) },
                                        onRestoreOriginal: { confirmRestoreOriginal(for: vm.cards[index].id) },
                                        hasOriginal: vm.hasOriginalArtwork(for: vm.cards[index].id),
                                        canRestoreOriginal: vm.canRestoreOriginal
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            }
        }
    }

    private func walletGridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(0, width - 40) // Grid's horizontal padding.
        let count = min(3, max(1, Int((availableWidth + 16) / (210 + 16))))
        return Array(repeating: GridItem(.flexible(minimum: 210, maximum: 300), spacing: 16), count: count)
    }

    var cardCountSummary: String {
        L("%@ cards · %@ selected", "\(vm.cards.count)", "\(vm.cards.filter(\.isSelected).count)")
    }

    var filteredCardIndices: [Int] {
        let query = cardSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(vm.cards.indices) }
        return vm.cards.indices.filter { index in
            vm.cards[index].id.localizedCaseInsensitiveContains(query) ||
            String(index + 1).contains(query)
        }
    }

    var hiddenReadyToFlashCount: Int {
        let visibleIndices = Set(filteredCardIndices)
        return vm.cards.indices.filter { index in
            !visibleIndices.contains(index) && vm.cards[index].isSelected && vm.cards[index].customImageURL != nil
        }.count
    }


    var walletPreview: some View {
        VStack(spacing: 0) {
            walletPhone
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                ForEach(0..<min(vm.cards.count, 5), id: \.self) { index in
                    Button { previewCardIndex = index } label: {
                        Circle()
                            .fill(index == previewCardIndex ? Color.brand : Color.secondary.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(L("Card #%@", String(index + 1)))
                }
            }
            .frame(height: 30)
        }
        .padding(16)
    }
}

extension ContentView {
    var walletPhone: some View {
        GeometryReader { proxy in
            let profile = PhonePreviewProfile.forDevice(vm.device)
            let width = min(profile.maxWidth, proxy.size.width - 20, (proxy.size.height - 8) / profile.aspectRatio)
            VStack(spacing: 0) {
                HStack {
                    Text("9:41").font(.system(size: 10, weight: .semibold))
                    Spacer()
                    Color.clear.frame(width: profile.front == .homeButton ? 45 : 75, height: 18)
                    Spacer()
                    Image(systemName: "wifi").font(.system(size: 10))
                    Image(systemName: "battery.100percent").font(.system(size: 10))
                }
                .padding(.horizontal, 18)
                .padding(.top, 15)
                HStack {
                    Text(L("Wallet"))
                        .font(.system(size: 22, weight: .bold))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                if vm.cards.isEmpty {
                    VStack(spacing: 9) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 40))
                        Text(L("Cards appear here"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("Scan or add a card to preview its artwork."))
                            .font(.system(size: 10))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let previewCount = min(vm.cards.count, 5)
                    let visibleIndices = (0..<previewCount).map { (previewCardIndex + $0) % previewCount }
                    ZStack(alignment: .top) {
                        ForEach(Array(visibleIndices.enumerated()).reversed(), id: \.element) { slot, index in
                            let card = vm.cards[index]
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(colors: [Color(red: 0.13 + Double(index % 3) * 0.08, green: 0.35, blue: 0.68), Color(red: 0.02, green: 0.09, blue: 0.21)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                if let image = card.customImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: width - 34, height: (width - 34) / 1.59)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    Text(L("Card #%@", String(index + 1)))
                                        .font(.system(size: 15, weight: .bold))
                                        .padding(12)
                                }
                            }
                            .frame(width: width - 34, height: (width - 34) / 1.59)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.3)))
                            .offset(y: CGFloat(slot) * (profile.front == .homeButton ? 42 : 53))
                            .onTapGesture { previewCardIndex = index }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 13)
                }
                Spacer(minLength: profile.front == .homeButton ? 43 : 16)
            }
            .foregroundStyle(.white)
            .frame(width: width, height: min(proxy.size.height - 4, width * profile.aspectRatio))
            .background(Color.black, in: RoundedRectangle(cornerRadius: profile.cornerRadius))
            .modifier(PhoneFrameChrome(profile: profile))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension ContentView {
    var scanningNoticeBanner: some View {
        NoticeBar(
            title: L("Live Scanner Active"),
            message: L("Double-click Side button (Apple Pay), pass Face ID, then tap your card.")
        ) {
            ProgressView().controlSize(.small)
        } trailing: {
            Button(L("Done")) { vm.stopCardScanning() }
                .controlSize(.small)
        }
    }

    var emptyStateView: some View {
        ContentUnavailableView {
            Label(L("No Cards Yet"), systemImage: "creditcard.viewfinder")
        } description: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) { Text("1."); LM("Click **Scan Cards** in the toolbar above.") }
                HStack(alignment: .top, spacing: 6) { Text("2."); LM("On your iPhone, **double-click the Side button** (Apple Pay), authenticate with **Face ID**, and **tap your card**.") }
                HStack(alignment: .top, spacing: 6) { Text("3."); Text(L("Your card will be detected immediately!")) }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 420)
        } actions: {
            Button(L("Start Scanning")) { vm.startCardScanning() }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canScanCards)
            Button(L("Add Hashes Manually")) { vm.showAddCardSheet = true }
                .buttonStyle(.bordered)
                .disabled(vm.activeProfileUDID == nil)
        }
    }
    
    // MARK: - Passcode Views
    
}

extension ContentView {
    func openCardImagePicker(for cardId: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a custom skin for card %@...", String(cardId.prefix(12)))
        if panel.runModal() == .OK, let url = panel.url {
            vm.setCardImage(for: cardId, url: url)
        }
    }
    
    /// Asks before writing the saved original back to the iPhone.
    func confirmRestoreOriginal(for cardId: String) {
        let alert = NSAlert()
        alert.messageText = L("Restore the original artwork?")
        alert.informativeText = L("FaceLift writes the artwork it saved before first changing this card back to %@. Designs you applied stay in the card's history.", vm.activeProfileName)
        alert.addButton(withTitle: L("Restore"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            vm.restoreOriginalArtwork(for: cardId)
        }
    }

    func openBulkImagePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a skin to assign to all selected cards...")
        if panel.runModal() == .OK, let url = panel.url {
            for card in vm.cards where card.isSelected {
                vm.setCardImage(for: card.id, url: url)
            }
        }
    }
    
}
