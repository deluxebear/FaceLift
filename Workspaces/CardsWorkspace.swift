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
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.35, blue: 0.75), Color(red: 0.03, green: 0.12, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let image = card.customImage {
                    GeometryReader { proxy in
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    VStack(alignment: .leading) {
                        Image(systemName: "wave.3.right")
                            .font(.title3)
                        Spacer()
                        Text(L("Card #%@", String(index + 1)))
                            .font(.title3.weight(.semibold))
                        Text(card.id.prefix(8) + "…" + card.id.suffix(6))
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .foregroundStyle(.white)
                    .padding(17)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                if card.customImage == nil {
                    Label(L("Add Artwork"), systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.18), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(12)
                }
            }
            .aspectRatio(1.59, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.28), lineWidth: 1))
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

            HStack(alignment: .top, spacing: 8) {
                Button { card.isSelected.toggle() } label: {
                    Image(systemName: card.isSelected ? "checkmark.square.fill" : "square")
                        .font(.title.weight(.medium))
                        .foregroundStyle(card.isSelected ? Color.brand : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(card.isSelected ? L("Remove from flash") : L("Include in flash"))
                .accessibilityLabel(Text(L("Card #%@", String(index + 1))))
                .accessibilityValue(Text(card.isSelected ? L("Selected for flash") : L("Not selected for flash")))
                .accessibilityHint(Text(card.isSelected ? L("Remove from flash") : L("Include in flash")))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Card #%@", String(index + 1)))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.primary)
                    Text(card.customImage == nil ? L("Artwork not set") : L("Artwork ready"))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 0)
                Menu {
                    Button(L("Change Skin"), action: onPickImage)
                    if card.customImage != nil { Button(L("Remove skin"), action: onClearImage) }
                    Button(L("Copy full hash")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(card.id, forType: .string)
                    }
                    Divider()
                    Button(L("Remove from list"), role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(nsColor: .separatorColor)))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 34)
            }
        }
        .padding(12)
        .faceLiftWorkspacePanel(cornerRadius: 17)
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(card.isSelected ? Color.brand.opacity(0.72) : Color(nsColor: .separatorColor), lineWidth: card.isSelected ? 1.5 : 1))
        .shadow(color: Color.brand.opacity(0.06), radius: 12, y: 5)
    }
}

extension ContentView {
    var walletWorkspace: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 9) {
                    Text(L("My Cards"))
                        .font(.title3.weight(.semibold))
                    Text("\(vm.cards.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 4)
                    CardSearchField(
                        text: $cardSearch,
                        placeholder: L("Search cards by hash or number"),
                        focusRequest: window.cardSearchFocusRequest
                    )
                    .frame(minWidth: 150, idealWidth: 240, maxWidth: 280)
                    .accessibilityLabel(Text(L("Search cards by hash or number")))
                    Menu {
                        Button(L("Select All")) { for i in vm.cards.indices { vm.cards[i].isSelected = true } }
                        Button(L("Deselect All")) { for i in vm.cards.indices { vm.cards[i].isSelected = false } }
                        Divider()
                        Button(L("Clear All"), role: .destructive) { vm.clearAllCards() }
                    } label: {
                        Label(L("Selection"), systemImage: "checklist")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(vm.cards.isEmpty)
                }
                if vm.isScanningCards { scanningNoticeBanner.clipShape(RoundedRectangle(cornerRadius: 12)) }
                if hiddenReadyToFlashCount > 0 {
                    Label {
                        Text(L("Search hides %@ selected card(s) ready to flash. Flashing still includes them.", "\(hiddenReadyToFlashCount)"))
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            Divider()

            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if vm.cards.isEmpty {
                            emptyStateView
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .faceLiftWorkspacePanel(cornerRadius: 18)
                        } else if filteredCardIndices.isEmpty {
                            ContentUnavailableView.search(text: cardSearch)
                                .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: walletGridColumns(for: geometry.size.width), spacing: 13) {
                                ForEach(filteredCardIndices, id: \.self) { index in
                                    WalletTileView(
                                        card: $vm.cards[index], index: index,
                                        onPickImage: { openCardImagePicker(for: vm.cards[index].id) },
                                        onClearImage: { vm.clearCardImage(for: vm.cards[index].id) },
                                        onDelete: { vm.deleteCard(id: vm.cards[index].id) },
                                        onStoreImage: { vm.storeSkin(for: vm.cards[index].id, url: $0) }
                                    )
                                }
                            }
                        }
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles.rectangle.stack")
                                .font(.title2)
                                .foregroundStyle(Color.brand)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L("Make a passcode theme"))
                                    .font(.title3.weight(.bold))
                                Text(L("Turn a poster into a keypad, or design each key."))
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Button(L("Open Creator")) { navigate(.creator) }
                                .faceLiftSecondaryButton()
                        }
                        .padding(17)
                        .faceLiftWorkspacePanel(cornerRadius: 13, tint: Color.brand.opacity(0.09))
                    }
                    .padding(.horizontal, 25)
                    .padding(.top, 15)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private func walletGridColumns(for width: CGFloat) -> [GridItem] {
        let availableWidth = max(0, width - 50) // Scroll content's horizontal padding.
        let count = min(3, max(1, Int((availableWidth + 13) / (210 + 13))))
        return Array(repeating: GridItem(.flexible(minimum: 210, maximum: 300), spacing: 13), count: count)
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
            HStack {
                Text(L("Live Preview"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.bottom, 13)
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
        HStack(spacing: 12) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.title)
                .foregroundStyle(Color.brand)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Live Scanner Active"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.brand)
                Text(L("Double-click Side button (Apple Pay), pass Face ID, then tap your card."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(L("Done")) {
                vm.stopCardScanning()
            }
            .faceLiftSecondaryButton()
            .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .faceLiftBannerSurface()
    }
    
    var emptyStateView: some View {
        VStack(spacing: 18) {
            Image(systemName: "creditcard.viewfinder")
                .font(.system(size: 54))
                .foregroundColor(.accentColor.opacity(0.8))
            
            Text(L("No Cards Detected Yet"))
                .font(.title3)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text("1.")
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    LM("Click **Scan Cards** in the toolbar above.")
                }
                HStack(alignment: .top, spacing: 10) {
                    Text("2.")
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    LM("On your iPhone, **double-click the Side button** (Apple Pay), authenticate with **Face ID**, and **tap your card**.")
                }
                HStack(alignment: .top, spacing: 10) {
                    Text("3.")
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)
                    Text(L("Your card will be detected immediately!"))
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .frame(maxWidth: 460)
            .padding(20)
            .faceLiftPanel(cornerRadius: 12, fallback: Color(NSColor.controlBackgroundColor))
            
            HStack(spacing: 12) {
                Button(action: { vm.startCardScanning() }) {
                    Label(L("Start Scanning"), systemImage: "wave.3.forward.circle.fill")
                        .fontWeight(.semibold)
                }
                .faceLiftProminentButton()
                .controlSize(.regular)
                .disabled(vm.device?.connected != true)
                
                Button(L("Add Hashes Manually")) {
                    vm.showAddCardSheet = true
                }
                .faceLiftSecondaryButton()
                .controlSize(.regular)
            }
        }
        .padding(40)
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
