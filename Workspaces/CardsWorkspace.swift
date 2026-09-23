import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WalletCardView: View {
    @ObservedObject private var language = AppLanguage.shared
    @Binding var card: CardItem
    let cardIndex: Int
    let onPickImage: () -> Void
    let onClearImage: () -> Void
    let onDelete: () -> Void
    var onStoreImage: (URL) -> Void = { _ in }
    
    @State private var isHovered = false
    @State private var isTargeted = false
    @State private var copied = false
    
    var body: some View {
        let _ = language.resolved
        return VStack(spacing: 10) {
            // Card Mockup
            ZStack {
                if let img = card.customImage {
                    // Custom Skin Applied
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 290, height: 182)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        
                        // Subtle Gloss
                        LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .black.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        
                        // Top Right Clear Button
                        Button(action: onClearImage) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.9))
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(10)
                        .help(L("Remove skin"))
                        
                        // Hover overlay: Change Skin
                        if isHovered {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Label(L("Change Skin"), systemImage: "photo.badge.arrow.forward")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .faceLiftCapsule(interactive: true, fallbackMaterial: .ultraThinMaterial)
                                        .shadow(radius: 4)
                                    Spacer()
                                }
                                .padding(.bottom, 12)
                            }
                        }
                    }
                } else {
                    // Empty / Placeholder Card Mockup
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(NSColor.controlBackgroundColor),
                                        Color(NSColor.windowBackgroundColor).opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isTargeted ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.4) : Color.secondary.opacity(0.2)),
                                style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: card.customImage == nil ? [6, 4] : [])
                            )
                        
                        // Card Chip & Contactless indicator
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "wave.3.right")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Spacer()
                                Image(systemName: "creditcard")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(14)
                            Spacer()
                        }
                        
                        // Center Action
                        VStack(spacing: 8) {
                            Image(systemName: isHovered || isTargeted ? "photo.badge.plus" : "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(isTargeted ? .accentColor : (isHovered ? .accentColor : .secondary.opacity(0.7)))
                                .scaleEffect(isHovered ? 1.08 : 1.0)
                                .animation(.spring(response: 0.3), value: isHovered)
                            
                            Text(isTargeted ? L("Drop image here") : L("Assign Card Skin"))
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text(L("Click to browse or drag image"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 290, height: 182)
                }
            }
            .frame(width: 290, height: 182)
            .shadow(color: .black.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 10 : 5, y: isHovered ? 5 : 2)
            .onHover { h in isHovered = h }
            .onTapGesture { onPickImage() }
            .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        var fileURL: URL?
                        if let url = item as? URL {
                            fileURL = url
                        } else if let data = item as? Data, let urlStr = String(data: data, encoding: .utf8), let url = URL(string: urlStr) {
                            fileURL = url
                        }
                        if let url = fileURL, let img = NSImage(contentsOf: url) {
                            Task { @MainActor in
                                card.customImageURL = url
                                card.customImage = img
                                card.isSelected = true
                                onStoreImage(url)
                            }
                        }
                    }
                    return true
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, _ in
                        if let url = item as? URL, let img = NSImage(contentsOf: url) {
                            Task { @MainActor in
                                card.customImageURL = url
                                card.customImage = img
                                card.isSelected = true
                                onStoreImage(url)
                            }
                        } else if let img = item as? NSImage {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("facelift_drop_\(UUID().uuidString).png")
                            if let tiff = img.tiffRepresentation,
                               let rep = NSBitmapImageRep(data: tiff),
                               let pngData = rep.representation(using: .png, properties: [:]) {
                                try? pngData.write(to: tempURL)
                            }
                            Task { @MainActor in
                                card.customImageURL = tempURL
                                card.customImage = img
                                card.isSelected = true
                                onStoreImage(tempURL)
                            }
                        }
                    }
                    return true
                }
                return false
            }
            
            // Bottom Info & Controls
            HStack(spacing: 8) {
                Toggle("", isOn: $card.isSelected)
                    .labelsHidden()
                    .help(L("Include in flash"))
                
                Text(L("Card #%@", String(cardIndex + 1)))
                    .font(.system(size: 12, weight: .semibold))
                
                // Monospace Hash Pill with Copy
                HStack(spacing: 4) {
                    Text(card.id.prefix(8) + "…" + card.id.suffix(6))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(card.id, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    }) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(copied ? L("Copied!") : L("Copy full hash"))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .faceLiftPanel(cornerRadius: 6, fallback: Color(NSColor.controlBackgroundColor))
                
                Spacer()
                
                // Status badge
                if card.customImage != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                        .help(L("Skin assigned and ready"))
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(L("Remove from list"))
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .faceLiftPanel(cornerRadius: 18, fallback: Color(NSColor.controlBackgroundColor).opacity(0.4))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(card.isSelected ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Main UI View

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
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(card.isSelected ? FaceLiftPalette.blue : FaceLiftPalette.muted)
                }
                .buttonStyle(.plain)
                .help(L("Include in flash"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Card #%@", String(index + 1)))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(FaceLiftPalette.ink)
                    Text(card.customImage == nil ? L("Artwork not set") : L("Artwork ready"))
                        .font(.caption)
                        .foregroundStyle(FaceLiftPalette.muted)
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
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(FaceLiftPalette.line))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 34)
            }
        }
        .padding(12)
        .faceLiftWorkspacePanel(cornerRadius: 17)
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(card.isSelected ? FaceLiftPalette.blue.opacity(0.72) : FaceLiftPalette.line, lineWidth: card.isSelected ? 1.5 : 1))
        .shadow(color: FaceLiftPalette.blue.opacity(0.06), radius: 12, y: 5)
    }
}

extension ContentView {
    var walletWorkspace: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    featureCard(title: L("Wallet Cards"), subtitle: L("Customize Apple Wallet artwork"), symbol: "creditcard.fill", selected: true) { navigate(.cards) }
                    featureCard(title: L("Lock Screen"), subtitle: L("Apply or create a passcode theme"), symbol: "lock.fill", selected: false) { navigate(.passcode) }
                }
                HStack(spacing: 9) {
                    Text(L("My Cards"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(FaceLiftPalette.ink)
                    Text("\(vm.cards.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(FaceLiftPalette.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.91, green: 0.94, blue: 0.99), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 4)
                    TextField(L("Search cards by hash or number"), text: $cardSearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                HStack(spacing: 8) {
                    Button { vm.toggleCardScanning() } label: {
                        Label(vm.isScanningCards ? L("Stop Scanning") : L("Scan Cards"), systemImage: vm.isScanningCards ? "stop.circle" : "wave.3.right")
                    }
                    .faceLiftSecondaryButton()
                    .disabled(vm.device?.connected != true)
                    Button { openBulkImagePicker() } label: { Label(L("Set Skin for All..."), systemImage: "photo") }
                        .faceLiftSecondaryButton()
                        .disabled(!vm.cards.contains(where: \.isSelected))
                    Button {
                        vm.queueSkinPulls(ids: vm.cards.filter(\.isSelected).map(\.id), replacingStored: true)
                    } label: {
                        Label(L("Read Selected from iPhone"), systemImage: "iphone.and.arrow.forward")
                    }
                    .faceLiftProminentButton()
                    .tint(FaceLiftPalette.blue)
                    .disabled(vm.device?.connected != true || vm.device?.isWiFi == true || vm.isPullingSkins || vm.isFlashing || !vm.cards.contains(where: \.isSelected))
                    .help(L("Read artwork for the selected cards only"))
                    Spacer(minLength: 0)
                    Menu {
                        Button(L("Select All")) { for i in vm.cards.indices { vm.cards[i].isSelected = true } }
                            .disabled(vm.cards.isEmpty)
                        Button(L("Deselect All")) { for i in vm.cards.indices { vm.cards[i].isSelected = false } }
                            .disabled(vm.cards.isEmpty)
                        Divider()
                        Button(L("Clear All"), role: .destructive) { vm.clearAllCards() }
                            .disabled(vm.cards.isEmpty)
                        Divider()
                        Button { vm.showAddCardSheet = true } label: { Label(L("Add Manually"), systemImage: "plus") }
                    } label: { Image(systemName: "ellipsis.circle").frame(width: 22) }
                }
                .controlSize(.regular)
                if vm.isScanningCards { scanningNoticeBanner.clipShape(RoundedRectangle(cornerRadius: 12)) }
            }
            .padding(.horizontal, 25)
            .padding(.top, 8)
            .padding(.bottom, 15)
            .overlay(alignment: .bottom) { FaceLiftPalette.line.opacity(0.75).frame(height: 1) }

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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 300), spacing: 13)], spacing: 13) {
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
                        .foregroundStyle(FaceLiftPalette.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Make a passcode theme"))
                            .font(.system(size: 14, weight: .bold))
                        Text(L("Turn a poster into a keypad, or design each key."))
                            .font(.caption)
                            .foregroundStyle(FaceLiftPalette.muted)
                    }
                    Spacer()
                    Button(L("Open Creator")) { navigate(.creator) }
                        .faceLiftSecondaryButton()
                }
                .padding(17)
                .faceLiftWorkspacePanel(cornerRadius: 13, tint: FaceLiftPalette.blue.opacity(0.09))
                }
                .padding(.horizontal, 25)
                .padding(.top, 15)
                .padding(.bottom, 24)
            }
        }
    }

    var filteredCardIndices: [Int] {
        let query = cardSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Array(vm.cards.indices) }
        return vm.cards.indices.filter { index in
            vm.cards[index].id.localizedCaseInsensitiveContains(query) ||
            String(index + 1).contains(query)
        }
    }

    func featureCard(title: String, subtitle: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? Color.white : FaceLiftPalette.blue)
                    .frame(width: 52, height: 52)
                    .background(selected ? FaceLiftPalette.blue : Color(red: 0.89, green: 0.93, blue: 1), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(FaceLiftPalette.ink)
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(FaceLiftPalette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(FaceLiftPalette.muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .faceLiftWorkspacePanel(cornerRadius: 14, tint: selected ? FaceLiftPalette.blue.opacity(0.12) : nil)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? FaceLiftPalette.blue.opacity(0.85) : FaceLiftPalette.line))
        }
        .buttonStyle(.plain)
    }

    var walletPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Live Preview"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FaceLiftPalette.ink)
                Spacer()
            }
            .padding(.bottom, 13)
            Picker("", selection: $vm.selectedTab) {
                Text(L("Wallet Cards")).tag(AppTab.walletCards)
                Text(L("Lock Screen")).tag(AppTab.passcodeThemes)
            }
            .pickerStyle(.segmented)
            .onChange(of: vm.selectedTab) { _, tab in if tab == .passcodeThemes { navigate(.passcode) } }
            .padding(.bottom, 18)
            walletPhone
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                ForEach(0..<min(vm.cards.count, 5), id: \.self) { index in
                    Button { previewCardIndex = index } label: {
                        Circle()
                            .fill(index == previewCardIndex ? FaceLiftPalette.blue : FaceLiftPalette.muted.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(L("Card #%@", String(index + 1)))
                }
            }
            .frame(height: 30)
        }
        .padding(17)
        .faceLiftWorkspacePanel(cornerRadius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(FaceLiftPalette.line))
        .shadow(color: FaceLiftPalette.blue.opacity(0.06), radius: 18, y: 6)
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
                .font(.system(size: 20))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Live Scanner Active"))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
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
