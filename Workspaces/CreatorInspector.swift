import SwiftUI
import AppKit
import UniformTypeIdentifiers

extension ContentView {
    var creatorInspector: some View {
        Form {
            Section {
                Picker(L("Mode"), selection: $vm.creatorSubMode) {
                    ForEach(CreatorSubMode.allCases) { subMode in
                        Text(subMode.title).tag(subMode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if vm.creatorSubMode == .posterSlice {
                posterSection
                slicingStyleSection
                framingSection
            } else {
                keysSection
                if let digit = vm.selectedKeyDigit,
                   vm.creatorRawIndividualImages[digit] != nil || vm.creatorCustomKeys[digit] != nil {
                    selectedKeySection(digit)
                }
            }
            flashTargetSection
        }
        .formStyle(.grouped)
    }

    private var posterSection: some View {
        Section(L("Poster Artwork")) {
            if let poster = vm.creatorPosterImage {
                HStack(spacing: 10) {
                    Image(nsImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
                    Text(L("Artwork Loaded"))
                    Spacer(minLength: 4)
                    Button(L("Change...")) { openPosterPicker() }
                    Menu {
                        Button(L("Use Chinese Numeral Example")) { vm.loadDefaultPoster() }
                        Divider()
                        Button(L("Remove"), role: .destructive) { vm.clearCreator() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("More"))
                }
            } else {
                LabeledContent {
                    Button(L("Choose Image...")) { openPosterPicker() }
                } label: {
                    Text(L("No poster selected"))
                        .foregroundStyle(.secondary)
                }
                Button(L("Use Chinese Numeral Example")) { vm.loadDefaultPoster() }
                    .buttonStyle(.link)
            }
        }
    }

    private var slicingStyleSection: some View {
        Section {
            Picker(L("Slicing Style"), selection: $vm.creatorMaskToCircles) {
                Text(L("Seamless Poster")).tag(false)
                Text(L("Circle Buttons")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: vm.creatorMaskToCircles) { _, _ in
                vm.updatePosterSlicing()
            }
        } header: {
            Text(L("Slicing Style"))
        } footer: {
            Text(vm.creatorMaskToCircles
                 ? L("Artwork is clipped into individual circular button icons.")
                 : L("Seamless artwork spans across dialer keys without circular cuts (Adobe Dog style)."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var framingSection: some View {
        Section {
            LabeledContent(L("Zoom")) {
                zoomSlider($vm.creatorPosterZoom)
            }
            .disabled(vm.creatorPosterImage == nil)
            .onChange(of: vm.creatorPosterZoom) { _, _ in
                vm.updatePosterSlicing()
            }
        } header: {
            HStack {
                Text(L("Framing"))
                Spacer()
                Button(L("Reset")) {
                    withAnimation(.spring()) {
                        vm.creatorPosterZoom = 1.0
                        vm.creatorPosterOffset = .zero
                        dragOffsetStart = .zero
                        vm.updatePosterSlicing()
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(vm.creatorPosterImage == nil)
            }
        } footer: {
            Text(L("Drag on the preview to reposition"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var keysSection: some View {
        Section {
            LabeledContent(L("Configured"), value: L("%@ of 10", "\(vm.creatorCustomKeys.count)"))
            HStack {
                if !vm.creatorSlicedKeys.isEmpty {
                    Button(L("Fill from Poster")) { vm.adoptPosterSlicesToIndividualKeys() }
                }
                Button(L("Clear All Keys")) { vm.clearAllIndividualKeys() }
                    .disabled(vm.creatorCustomKeys.isEmpty)
            }
        } header: {
            Text(L("Individual Keys"))
        } footer: {
            Text(L("Click any key on the dialer to select it, pan the image, adjust zoom, or drop files."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectedKeySection(_ digit: String) -> some View {
        Section {
            LabeledContent(L("Zoom")) {
                zoomSlider(Binding(
                    get: { vm.creatorIndividualZooms[digit] ?? 1.0 },
                    set: { newValue in
                        vm.creatorIndividualZooms[digit] = newValue
                        vm.updateIndividualKey(digit: digit)
                    }
                ))
            }
            HStack {
                Button(L("Change Image...")) { openIndividualKeyPicker(for: digit) }
                Button(L("Reset")) { withAnimation(.spring()) { resetIndividualKey(digit) } }
                Button(L("Remove")) { vm.clearIndividualKey(digit: digit) }
            }
            .controlSize(.small)
        } header: {
            HStack {
                Text(L("Key %@", digit))
                Spacer()
                Button(L("Done")) { vm.selectedKeyDigit = nil }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        } footer: {
            Text(L("Drag Key %@ on dialer preview to reposition", digit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func zoomSlider(_ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: 0.5...3.0, step: 0.05) {
                Text(L("Zoom"))
            } minimumValueLabel: {
                Image(systemName: "minus.magnifyingglass")
            } maximumValueLabel: {
                Image(systemName: "plus.magnifyingglass")
            }
            .labelsHidden()
            .frame(minWidth: 120, maxWidth: .infinity)
            Text(String(format: "%.1fx", value.wrappedValue))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    func resetIndividualKey(_ digit: String) {
        vm.creatorIndividualOffsets[digit] = .zero
        vm.creatorIndividualZooms[digit] = 1.0
        dragKeyStartOffsets[digit] = .zero
        vm.updateIndividualKey(digit: digit)
    }
}
