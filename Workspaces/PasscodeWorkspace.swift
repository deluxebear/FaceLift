import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var passcodePreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("Live Preview"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(FaceLiftPalette.ink)
                Spacer()
            }
            .padding(.bottom, 13)
            Text(vm.device?.connected == true ? (vm.device?.name ?? "iPhone") : L("iPhone Preview"))
                .font(.caption)
                .foregroundStyle(FaceLiftPalette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 11)

            phoneMockupContainer {
                if vm.passcodeTabMode == .applyTheme {
                    applyThemeDialerCanvas
                } else {
                    creatorDialerCanvas
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.passcodeTabMode == .applyTheme {
                Button { openPasscodeThemePicker() } label: {
                    Label(vm.loadedPasscodeTheme == nil ? L("Choose .passthm File...") : L("Change..."), systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .faceLiftSecondaryButton()
            } else {
                Button { openSavePasscodeThemePanel() } label: {
                    Label(L("Export .passthm..."), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .faceLiftSecondaryButton()
                .disabled(vm.effectiveCreatorKeys.isEmpty)
            }
        }
        .padding(16)
    }
}

extension ContentView {
    var passcodeWorkspace: some View {
        ScrollView {
            passcodeThemeWorkspaceView
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
    }
}

extension ContentView {
    
    var passcodeThemeWorkspaceView: some View {
        Group {
            if vm.passcodeTabMode == .applyTheme {
                passcodeApplyThemeWorkspaceView
            } else {
                passcodeThemeCreatorWorkspaceView
            }
        }
    }
    
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
                            .font(.system(size: 28))
                            .foregroundColor(FaceLiftPalette.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(theme.name)
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Text(theme.detectedVersion)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(FaceLiftPalette.blue.opacity(0.15))
                                .foregroundColor(FaceLiftPalette.blue)
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
                        .tint(FaceLiftPalette.blue)
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
                        .foregroundColor(FaceLiftPalette.blue)
                    
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
                    .tint(FaceLiftPalette.blue)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isTargetedTheme ? FaceLiftPalette.blue : FaceLiftPalette.blue.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
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
    
    var applyThemeDialerCanvas: some View {
        ZStack {
            ForEach(KeypadLayout.allButtons) { btn in
                let cellX = CGFloat(btn.col) * KeypadLayout.colWidth
                let cellY = CGFloat(btn.row) * KeypadLayout.rowHeight
                let centerX = cellX + KeypadLayout.colWidth / 2.0
                let centerY = cellY + KeypadLayout.rowHeight / 2.0
                
                ZStack {
                    KeypadKeySurface()
                    
                    if let img = vm.loadedPasscodeTheme?.keysPreview[btn.digit] {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                            .clipShape(Circle())
                    }
                    
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                    
                    VStack(spacing: 1) {
                        Text(btn.digit)
                            .font(.system(size: 28, weight: .light))
                            .foregroundColor(.white)
                        if !btn.letters.isEmpty {
                            Text(btn.letters)
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1)
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                .position(x: centerX, y: centerY)
            }
        }
        .frame(width: KeypadLayout.gridWidth, height: KeypadLayout.gridHeight)
        .faceLiftGlassGroup()
    }
    
    // MARK: - Theme Creator Mode
    
    var passcodeThemeCreatorWorkspaceView: some View {
        VStack(alignment: .leading, spacing: 14) {
            creatorControlsCard
            targetSettingsCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var creatorControlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Mode Selector: Poster Slice vs Individual Keys
            Picker("", selection: $vm.creatorSubMode) {
                ForEach(CreatorSubMode.allCases) { subMode in
                    Text(subMode.title).tag(subMode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            
            Divider()
            
            if vm.creatorSubMode == .posterSlice {
                // 1. Poster Source Section
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Poster Artwork"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    if let poster = vm.creatorPosterImage {
                        HStack(spacing: 12) {
                            Image(nsImage: poster)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 50, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(FaceLiftPalette.blue.opacity(0.4), lineWidth: 1)
                                )
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L("Artwork Loaded"))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                HStack(spacing: 8) {
                                    Button(L("Change...")) {
                                        openPosterPicker()
                                    }
                                    .faceLiftSecondaryButton()
                                    .controlSize(.small)

                                    Button(L("Remove")) {
                                        vm.clearCreator()
                                    }
                                    .faceLiftSecondaryButton()
                                    .controlSize(.small)
                                }

                                Button(L("Use Chinese Numeral Example")) {
                                    vm.loadDefaultPoster()
                                }
                                .faceLiftSecondaryButton()
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .faceLiftPanel(cornerRadius: 10, fallback: Color(NSColor.controlBackgroundColor))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 26))
                                .foregroundColor(FaceLiftPalette.blue)
                            
                            Text(L("Drop poster or wallpaper here"))
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Button(L("Choose Image...")) {
                                openPosterPicker()
                            }
                            .faceLiftProminentButton()
                            .tint(FaceLiftPalette.blue)
                            .controlSize(.regular)

                            Button(L("Use Chinese Numeral Example")) {
                                vm.loadDefaultPoster()
                            }
                            .faceLiftSecondaryButton()
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isTargetedPoster ? FaceLiftPalette.blue : FaceLiftPalette.blue.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                                .background(faceLiftDropZoneFill(cornerRadius: 10))
                        )
                        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isTargetedPoster) { providers in
                            handlePosterDrop(providers: providers)
                        }
                    }
                }
                
                Divider()
                
                // 2. Style Section
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Slicing Style"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $vm.creatorMaskToCircles) {
                        Text(L("Seamless Poster")).tag(false)
                        Text(L("Circle Buttons")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: vm.creatorMaskToCircles) { _, _ in
                        vm.updatePosterSlicing()
                    }
                    
                    Text(vm.creatorMaskToCircles ? L("Artwork is clipped into individual circular button icons.") : L("Seamless artwork spans across dialer keys without circular cuts (Adobe Dog style)."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Divider()
                
                // 3. Framing & Zoom Section
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L("Zoom & Framing"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(L("Reset Position")) {
                            withAnimation(.spring()) {
                                vm.creatorPosterZoom = 1.0
                                vm.creatorPosterOffset = .zero
                                dragOffsetStart = .zero
                                vm.updatePosterSlicing()
                            }
                        }
                        .buttonStyle(.link)
                        .font(.caption2)
                        .disabled(vm.creatorPosterImage == nil)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "minus.magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Slider(value: $vm.creatorPosterZoom, in: 0.5...3.0, step: 0.05) {
                            Text(L("Zoom"))
                        }
                        .onChange(of: vm.creatorPosterZoom) { _, _ in
                            vm.updatePosterSlicing()
                        }
                        .disabled(vm.creatorPosterImage == nil)
                        
                        Image(systemName: "plus.magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text(String(format: "%.1fx", vm.creatorPosterZoom))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(width: 32, alignment: .trailing)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                        Text(L("Drag anywhere on the dialer preview to reposition"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // Individual Keys Mode Controls
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(L("Individual Keys"))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let sel = vm.selectedKeyDigit {
                            Button(L("Deselect Key %@", sel)) {
                                vm.selectedKeyDigit = nil
                            }
                            .buttonStyle(.link)
                            .font(.caption2)
                        }
                    }
                    
                    if let selDigit = vm.selectedKeyDigit, vm.creatorRawIndividualImages[selDigit] != nil || vm.creatorCustomKeys[selDigit] != nil {
                        // Per-key framing controls
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(L("Key %@ Framing", selDigit), systemImage: "crop")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(FaceLiftPalette.blue)
                                Spacer()
                                Button(L("Reset")) {
                                    withAnimation(.spring()) {
                                        vm.creatorIndividualOffsets[selDigit] = .zero
                                        vm.creatorIndividualZooms[selDigit] = 1.0
                                        dragKeyStartOffsets[selDigit] = .zero
                                        vm.updateIndividualKey(digit: selDigit)
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption2)
                            }
                            
                            // Zoom Slider for the selected key
                            let zoomVal = vm.creatorIndividualZooms[selDigit] ?? 1.0
                            HStack(spacing: 8) {
                                Image(systemName: "minus.magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                Slider(
                                    value: Binding(
                                        get: { vm.creatorIndividualZooms[selDigit] ?? 1.0 },
                                        set: { newVal in
                                            vm.creatorIndividualZooms[selDigit] = newVal
                                            vm.updateIndividualKey(digit: selDigit)
                                        }
                                    ),
                                    in: 0.5...3.0,
                                    step: 0.05
                                )
                                
                                Image(systemName: "plus.magnifyingglass")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                
                                Text(String(format: "%.1fx", zoomVal))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .frame(width: 32, alignment: .trailing)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "hand.draw")
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                                Text(L("Drag Key %@ on dialer preview to reposition", selDigit))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 8) {
                                Button(L("Change Image...")) {
                                    openIndividualKeyPicker(for: selDigit)
                                }
                                .faceLiftSecondaryButton()
                                .controlSize(.small)
                                
                                Button(L("Remove")) {
                                    vm.clearIndividualKey(digit: selDigit)
                                }
                                .faceLiftSecondaryButton()
                                .controlSize(.small)
                            }
                            .padding(.top, 2)
                        }
                        .padding(10)
                        .faceLiftPanel(cornerRadius: 10, fallback: Color(NSColor.controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(FaceLiftPalette.blue.opacity(0.35), lineWidth: 1)
                        )
                        
                        Divider()
                    }
                    
                    Text(L("Click any key on the dialer to select it, pan the image, adjust zoom, or drop files."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                        Text(L("%@ of 10 keys configured", "\(vm.creatorCustomKeys.count)"))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    HStack(spacing: 8) {
                        if !vm.creatorSlicedKeys.isEmpty {
                            Button(L("Fill from Poster")) {
                                vm.adoptPosterSlicesToIndividualKeys()
                            }
                            .faceLiftSecondaryButton()
                            .controlSize(.regular)
                        }
                        
                        Button(L("Clear All Keys")) {
                            vm.clearAllIndividualKeys()
                        }
                        .faceLiftSecondaryButton()
                        .controlSize(.regular)
                        .disabled(vm.creatorCustomKeys.isEmpty)
                    }
                }
            }
        }
        .padding(14)
        .faceLiftPanel(cornerRadius: 14, fallback: Color(NSColor.controlBackgroundColor).opacity(0.5))
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
        .faceLiftGlassGroup()
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
            handlePosterDrop(providers: providers)
        }
    }
    
    func creatorButtonView(for btn: KeypadButtonGeometry) -> some View {
        let customIndividualImage = vm.creatorCustomKeys[btn.digit]
        let slicedImage = vm.creatorSlicedKeys[btn.digit]
        
        return ZStack {
            if vm.creatorSubMode == .posterSlice {
                if vm.creatorMaskToCircles {
                    // Circular Cutouts mode: display sliced circular preview
                    KeypadKeySurface()
                    
                    if let img = slicedImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                            .clipShape(Circle())
                    }
                    
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                } else {
                    // Seamless Poster mode: frosted translucent circle indicator
                    KeypadKeySurface()
                    
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                }
            } else {
                // Individual Keys mode
                let isSelected = (vm.selectedKeyDigit == btn.digit)
                KeypadKeySurface()
                
                if let img = customIndividualImage {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                }
                
                Circle()
                    .stroke(isSelected ? FaceLiftPalette.blue : Color.white.opacity(0.3), lineWidth: isSelected ? 2.5 : 1)
                    .frame(width: KeypadLayout.buttonDiameter, height: KeypadLayout.buttonDiameter)
                    .shadow(color: isSelected ? FaceLiftPalette.blue.opacity(0.8) : Color.clear, radius: 4)
            }
            
            // Authentic Digits & Letters Typography
            if !(vm.creatorUsesDefaultPoster && vm.creatorSubMode == .posterSlice) {
                VStack(spacing: 1) {
                    Text(btn.digit)
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white)
                    if !btn.letters.isEmpty {
                        Text(btn.letters)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
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
                        vm.creatorIndividualOffsets[btn.digit] = .zero
                        vm.creatorIndividualZooms[btn.digit] = 1.0
                        dragKeyStartOffsets[btn.digit] = .zero
                        vm.updateIndividualKey(digit: btn.digit)
                    }
                    Button(L("Clear Key %@", btn.digit)) {
                        vm.clearIndividualKey(digit: btn.digit)
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: nil) { providers in
            if vm.creatorSubMode == .individualKeys {
                return handleIndividualKeyDrop(digit: btn.digit, providers: providers)
            }
            return false
        }
    }
    
    // MARK: - Authentic Phone Lock Screen Mockup Container
    
    func phoneMockupContainer<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            let profile = PhonePreviewProfile.forDevice(vm.device)
            let baseWidth: CGFloat = 326
            let baseHeight = baseWidth * profile.aspectRatio
            let scale = max(0.1, min(1, (proxy.size.width - 12) / baseWidth, (proxy.size.height - 12) / baseHeight))

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
            .scaleEffect(scale)
            .frame(width: baseWidth * scale, height: baseHeight * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // MARK: - Passcode Target Configuration Box
    
    var targetSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(FaceLiftPalette.blue)
                    .font(.system(size: 13, weight: .semibold))
                Text(L("Flash & Language Target"))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            // 1. Language Target Selector
            VStack(alignment: .leading, spacing: 4) {
                Text(L("System Language:"))
                    .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 10))
                    .foregroundColor(vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both ? .secondary : .orange)
                    .padding(.top, 1)
                
                if vm.passcodeLanguageTarget == .all && vm.passcodeBoldTarget == .both {
                    Text(L("Universal mode flashes ~600 files for all languages & Bold text. Selecting a specific language (e.g. Ukrainian) speeds up flashing dramatically."))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("Fast mode selected: only targets %@ with %@.", vm.passcodeLanguageTarget.title, vm.passcodeBoldTarget.title))
                        .font(.system(size: 9))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .faceLiftPanel(cornerRadius: 10, fallback: Color(NSColor.controlBackgroundColor).opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(FaceLiftPalette.blue.opacity(0.3), lineWidth: 1))
    }
    
}

extension ContentView {
    func openPasscodeThemePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "passthm") ?? .data,
            UTType(filenameExtension: "passtheme") ?? .data,
            .zip
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a .passthm passcode theme package...")
        if panel.runModal() == .OK, let url = panel.url {
            vm.inspectPasscodeTheme(url: url)
        }
    }
    
    func openPosterPicker() {
        let panel = NSOpenPanel()
        panel.title = L("Choose Poster Image")
        panel.message = L("Select a wallpaper or photo to slice for the passcode keypad...")
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "heic") ?? .image,
            UTType(filenameExtension: "webp") ?? .image,
            .image
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            vm.setPosterImage(img)
        }
    }
    
    func openIndividualKeyPicker(for digit: String) {
        let panel = NSOpenPanel()
        panel.title = L("Choose Icon for Key %@", digit)
        panel.message = L("Select an icon or image for key %@...", digit)
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType(filenameExtension: "heic") ?? .image,
            UTType(filenameExtension: "webp") ?? .image,
            .image
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            vm.setIndividualKey(digit: digit, image: img)
        }
    }
    
    func openSavePasscodeThemePanel() {
        let keys = vm.effectiveCreatorKeys
        guard !keys.isEmpty else {
            vm.errorMessage = L("Please configure at least one key before exporting.")
            return
        }
        
        let panel = NSSavePanel()
        panel.title = L("Save Passcode Theme")
        panel.prompt = L("Export")
        panel.nameFieldStringValue = "CustomTheme.passthm"
        panel.allowedContentTypes = [UTType(filenameExtension: "passthm") ?? .data]
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try PasscodeThemeExporter.exportTheme(keys: keys, targetURL: url)
                vm.setStatus("Theme exported successfully to %@", url.lastPathComponent)
                vm.log("Exported .passthm to %@", url.path)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                vm.errorMessage = L("Failed to export theme: %@", error.localizedDescription)
            }
        }
    }
    
    func handlePosterDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        loadImage(from: provider) { img in
            if let img = img {
                vm.setPosterImage(img)
            }
        }
        return true
    }
    
    func handleIndividualKeyDrop(digit: String, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        loadImage(from: provider) { img in
            if let img = img {
                vm.setIndividualKey(digit: digit, image: img)
            }
        }
        return true
    }
    
    func loadImage(from provider: NSItemProvider, completion: @escaping (NSImage?) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url, let img = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { completion(img) }
                    return
                }
                if provider.canLoadObject(ofClass: NSImage.self) {
                    _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                        DispatchQueue.main.async { completion(img as? NSImage) }
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            }
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                DispatchQueue.main.async { completion(img as? NSImage) }
            }
        } else {
            completion(nil)
        }
    }
}
