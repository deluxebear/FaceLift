import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct KeypadDigitLabel: View {
    let button: KeypadButtonGeometry

    var body: some View {
        VStack(spacing: 0) {
            Text(button.digit)
                .font(.system(size: 30, weight: .light))
            if !button.letters.isEmpty {
                Text(button.letters)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.75), radius: 2, y: 1)
    }
}

extension ContentView {
    /// Lock Screen / Creator detail area: the phone mockup centered on a
    /// canvas that also accepts the page's file drops.
    var themeCanvas: some View {
        let isApply = vm.passcodeTabMode == .applyTheme
        return VStack(spacing: 12) {
            phoneMockupContainer {
                if isApply {
                    applyThemeDialerCanvas
                } else {
                    creatorDialerCanvas
                }
            }
            VStack(spacing: 4) {
                if isApply && vm.loadedPasscodeTheme == nil {
                    Text(L("Drop .passthm file here"))
                        .font(.callout.weight(.medium))
                }
                Text(canvasCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if isCanvasTargeted {
                Rectangle().strokeBorder(Color.brand, lineWidth: 3)
            }
        }
        .onDrop(
            of: isApply ? [UTType.fileURL] : [UTType.fileURL, UTType.image],
            isTargeted: $isCanvasTargeted
        ) { providers in
            isApply ? handleThemeDrop(providers: providers) : handleCreatorDrop(providers: providers, keyDigit: nil)
        }
    }

    var canvasCaption: String {
        vm.device?.connected == true
            ? L("Previewing at %@ size", vm.device?.name ?? "iPhone")
            : L("iPhone Preview")
    }

    var applyThemeDialerCanvas: some View {
        ZStack {
            ForEach(KeypadLayout.allButtons) { btn in
                let cellX = CGFloat(btn.col) * KeypadLayout.colWidth
                let cellY = CGFloat(btn.row) * KeypadLayout.rowHeight
                let centerX = cellX + KeypadLayout.colWidth / 2.0
                let centerY = cellY + KeypadLayout.rowHeight / 2.0
                
                ZStack {
                    // A theme key image replaces the whole stock button,
                    // so the default surface, outline and label only show
                    // when no theme image is available for this digit.
                    if let img = vm.loadedPasscodeTheme?.keysPreview[btn.digit] {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                            .clipShape(Circle())
                    } else {
                        KeypadKeySurface()

                        Circle()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)

                        KeypadDigitLabel(button: btn)
                    }
                }
                .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                .position(x: centerX, y: centerY)
            }
        }
        .frame(width: KeypadLayout.gridWidth, height: KeypadLayout.gridHeight)
    }

    func scaledPosterDimensions(for poster: NSImage) -> (width: CGFloat, height: CGFloat) {
        let imgAspect = poster.size.width / poster.size.height
        let gridAspect = KeypadLayout.gridWidth / KeypadLayout.gridHeight
        let zoom = CGFloat(max(0.1, vm.creatorPosterZoom))
        if imgAspect > gridAspect {
            let h = KeypadLayout.gridHeight * zoom
            return (width: h * imgAspect, height: h)
        } else {
            let w = KeypadLayout.gridWidth * zoom
            return (width: w, height: w / imgAspect)
        }
    }
    
    var creatorDialerCanvas: some View {
        ZStack {
            // Layer 1: Background Poster Image (Seamless Poster Mode)
            if vm.creatorSubMode == .posterSlice, let poster = vm.creatorPosterImage, !vm.creatorMaskToCircles {
                let dims = scaledPosterDimensions(for: poster)
                Image(nsImage: poster)
                    .resizable()
                    .frame(width: dims.width, height: dims.height)
                    .position(
                        x: KeypadLayout.gridWidth / 2.0 + vm.creatorPosterOffset.x,
                        y: KeypadLayout.gridHeight / 2.0 + vm.creatorPosterOffset.y
                    )
            }
            
            // Layer 2: 10 Buttons laid out in exact cell frames
            ForEach(KeypadLayout.allButtons) { btn in
                let cellX = CGFloat(btn.col) * KeypadLayout.colWidth
                let cellY = CGFloat(btn.row) * KeypadLayout.rowHeight
                let centerX = cellX + KeypadLayout.colWidth / 2.0
                let centerY = cellY + KeypadLayout.rowHeight / 2.0
                
                creatorButtonView(for: btn)
                    .position(x: centerX, y: centerY)
            }
        }
        .frame(width: KeypadLayout.gridWidth, height: KeypadLayout.gridHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if vm.creatorSubMode == .posterSlice && vm.creatorPosterImage != nil {
                        vm.creatorPosterOffset = CGPoint(
                            x: dragOffsetStart.x + value.translation.width,
                            y: dragOffsetStart.y + value.translation.height
                        )
                        vm.updatePosterSlicing()
                    }
                }
                .onEnded { _ in
                    dragOffsetStart = vm.creatorPosterOffset
                }
        )
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: nil) { providers in
            handleCreatorDrop(providers: providers, keyDigit: nil)
        }
    }
    
    func creatorButtonView(for btn: KeypadButtonGeometry) -> some View {
        let customIndividualImage = vm.creatorCustomKeys[btn.digit]
        let slicedImage = vm.creatorSlicedKeys[btn.digit]
        
        return ZStack {
            if vm.creatorSubMode == .posterSlice {
                if vm.creatorMaskToCircles {
                    // Circular Cutouts mode: display sliced circular preview
                    if let img = slicedImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                            .clipShape(Circle())
                    } else {
                        KeypadKeySurface()

                        Circle()
                            .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                    }
                } else {
                    // Seamless Poster mode: a light outline keeps the artwork visible.
                    KeypadKeySurface()
                    
                    Circle()
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                }
            } else {
                // Individual Keys mode
                let isSelected = (vm.selectedKeyDigit == btn.digit)
                if let img = customIndividualImage {
                    // The key image replaces the stock button on device.
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                } else {
                    KeypadKeySurface()
                }

                if isSelected || customIndividualImage == nil {
                    Circle()
                        .strokeBorder(isSelected ? Color.brand : Color.white.opacity(0.65), lineWidth: isSelected ? 2.5 : 1)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                        .shadow(color: isSelected ? Color.brand.opacity(0.8) : Color.clear, radius: 4)
                }
            }

            // Stock digits & letters only for keys without artwork; exported
            // key images replace the whole button, labels included.
            let keyImage = vm.creatorSubMode == .posterSlice ? slicedImage : customIndividualImage
            if keyImage == nil {
                KeypadDigitLabel(button: btn)
            }
        }
        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if vm.creatorSubMode == .individualKeys && (vm.creatorRawIndividualImages[btn.digit] != nil || vm.creatorCustomKeys[btn.digit] != nil) {
                        if vm.selectedKeyDigit != btn.digit {
                            vm.selectedKeyDigit = btn.digit
                        }
                        let start = dragKeyStartOffsets[btn.digit] ?? (vm.creatorIndividualOffsets[btn.digit] ?? .zero)
                        vm.creatorIndividualOffsets[btn.digit] = CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        )
                        vm.updateIndividualKey(digit: btn.digit)
                    }
                }
                .onEnded { _ in
                    if let cur = vm.creatorIndividualOffsets[btn.digit] {
                        dragKeyStartOffsets[btn.digit] = cur
                    }
                }
        )
        .onTapGesture {
            if vm.creatorSubMode == .individualKeys {
                if customIndividualImage == nil && vm.creatorRawIndividualImages[btn.digit] == nil {
                    openIndividualKeyPicker(for: btn.digit)
                } else {
                    vm.selectedKeyDigit = (vm.selectedKeyDigit == btn.digit ? nil : btn.digit)
                }
            }
        }
        .contextMenu {
            if vm.creatorSubMode == .individualKeys {
                Button(L("Change Key %@...", btn.digit)) {
                    openIndividualKeyPicker(for: btn.digit)
                }
                if customIndividualImage != nil {
                    Button(L("Reset Position & Zoom")) {
                        resetIndividualKey(btn.digit)
                    }
                    Button(L("Clear Key %@", btn.digit)) {
                        vm.clearIndividualKey(digit: btn.digit)
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: nil) { providers in
            handleCreatorDrop(providers: providers, keyDigit: btn.digit)
        }
    }
    
    // MARK: - Authentic Phone Lock Screen Mockup Container
    
    func phoneMockupContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            let profile = PhonePreviewProfile.forDevice(vm.device)
            let baseWidth: CGFloat = 326
            let baseHeight = baseWidth * profile.aspectRatio
            let scale = max(0.1, min(1.25, (proxy.size.width - 12) / baseWidth, (proxy.size.height - 12) / baseHeight))

            ZStack {
                RoundedRectangle(cornerRadius: profile.cornerRadius)
                    .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear, Color.black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: profile.cornerRadius))

                VStack(spacing: 0) {
                    HStack {
                        Text("9:41")
                        Spacer()
                        Color.clear.frame(width: profile.front == .homeButton ? 45 : 75, height: 18)
                        Spacer()
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100percent")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 17)

                    VStack(spacing: 5) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                        Text(L("Enter Passcode"))
                            .font(.system(size: 15))
                        HStack(spacing: 10) {
                            ForEach(0..<6, id: \.self) { _ in
                                Circle().stroke(.white.opacity(0.75), lineWidth: 1.4).frame(width: 9, height: 9)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.top, 35)

                    Spacer(minLength: 8)
                    content()
                        .frame(width: KeypadLayout.gridWidth, height: KeypadLayout.gridHeight)
                    Spacer(minLength: 8)

                    HStack {
                        Text(L("Emergency"))
                        Spacer()
                        Text(L("Cancel"))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 28)
                    .padding(.bottom, profile.front == .homeButton ? 52 : 27)
                }
            }
            .frame(width: baseWidth, height: baseHeight)
            .modifier(PhoneFrameChrome(profile: profile))
            // The iPhone keypad renders light glass keys regardless of the Mac's appearance.
            .environment(\.colorScheme, .light)
            .scaleEffect(scale)
            .frame(width: baseWidth * scale, height: baseHeight * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
