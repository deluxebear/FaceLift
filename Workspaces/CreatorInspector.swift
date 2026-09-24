import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
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
                                        .stroke(Color.brand.opacity(0.4), lineWidth: 1)
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
                                .font(.largeTitle)
                                .foregroundColor(Color.brand)
                            
                            Text(L("Drop poster or wallpaper here"))
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Button(L("Choose Image...")) {
                                openPosterPicker()
                            }
                            .faceLiftProminentButton()
                            .tint(Color.brand)
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
                                .stroke(isTargetedPoster ? Color.brand : Color.brand.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
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
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
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
                                    .foregroundColor(Color.brand)
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
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
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
                                .stroke(Color.brand.opacity(0.35), lineWidth: 1)
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
}
