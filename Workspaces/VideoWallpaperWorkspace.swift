import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// A plain player layer keeps media controls and letterboxing outside the
/// exported image. The player item's composition supplies the actual crop.
private struct WallpaperPlayerView: NSViewRepresentable {
    let player: AVPlayer?

    final class PlayerSurface: NSView {
        let playerLayer = AVPlayerLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() { super.layout(); playerLayer.frame = bounds }
    }

    func makeNSView(context: Context) -> PlayerSurface { PlayerSurface(frame: .zero) }
    func updateNSView(_ view: PlayerSurface, context: Context) { view.playerLayer.player = player }
    static func dismantleNSView(_ view: PlayerSurface, coordinator: ()) { view.playerLayer.player = nil }
}

extension ContentView {
    var videoWallpaperWorkspace: some View {
        ScrollView {
            VStack(spacing: 16) {
                if wallpaper.source == nil {
                    ContentUnavailableView {
                        Label(L("Video to Live Photo"), systemImage: "livephoto")
                    } description: {
                        Text(L("Drop a video here, then choose a short clip for your iPhone Lock Screen."))
                    } actions: {
                        Button(L("Choose Video...")) { perform(.importVideo) }
                            .buttonStyle(.borderedProminent)
                            .disabled(wallpaper.isBusy)
                    }
                    .frame(minHeight: 380)
                } else {
                    wallpaperPhonePreview
                    HStack(spacing: 12) {
                        Button { wallpaper.togglePlayback() } label: {
                            Label(wallpaper.isPlaying ? L("Show Cover") : L("Play Selected Clip"),
                                  systemImage: wallpaper.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .disabled(!wallpaper.previewReady || wallpaper.isBusy)
                        Text(L("Preview only · Clock and controls are not exported"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let source = wallpaper.source {
                        Text(source.url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if wallpaper.operation == .generating {
                    ProgressView(value: wallpaper.progress)
                        .frame(maxWidth: 420)
                    Text(L("Creating Live Photo..."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if wallpaper.generated != nil {
                    wallpaperResultNotice
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if isWallpaperTargeted { Rectangle().strokeBorder(Color.brand, lineWidth: 3) }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isWallpaperTargeted) { providers in
            guard !wallpaper.isBusy, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.isFileURL else { return }
                Task { @MainActor in wallpaper.load(url) }
            }
            return true
        }
        .onDisappear { wallpaper.pause() }
    }

    private var wallpaperPhonePreview: some View {
        let aspect = wallpaper.format.size.height / wallpaper.format.size.width
        let profile = PhonePreviewProfile.forDevice(vm.device)
        return WallpaperPlayerView(player: wallpaper.player)
            .frame(width: 220, height: 220 * aspect)
            .overlay(alignment: .top) {
                VStack(spacing: 2) {
                    Text(L("Lock Screen Preview")).font(.caption)
                    Text("9:41").font(.system(size: 48, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3)
                .padding(.top, profile.front == .homeButton ? 36 : 50)
                .allowsHitTesting(false)
            }
            .overlay {
                if !wallpaper.previewReady { ProgressView().tint(.white) }
            }
            .modifier(PhoneFrameChrome(profile: profile))
            .accessibilityLabel(L("Lock Screen Preview"))
    }

    private var wallpaperResultNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(wallpaper.status, systemImage: "checkmark.circle")
                .font(.headline)
            Text(wallpaper.resultState == .saved
                 ? L("If iCloud Photos is enabled on this Mac and iPhone with the same Apple Account, wait for the Live Photo to appear on your iPhone. FaceLift cannot check sync completion.")
                 : L("The photo and video passed Live Photo format validation. Motion wallpaper eligibility still needs to be checked on your iPhone."))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(L("Save to Mac Photos")) { perform(.saveLivePhoto) }
                    .disabled(!wallpaper.canSave)
                Button(L("Export Paired Files...")) { perform(.exportLivePhoto) }
                    .disabled(!wallpaper.canExport)
                if let directory = wallpaper.exportedDirectory {
                    Button(L("Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    var videoWallpaperInspector: some View {
        Form {
            if let source = wallpaper.source {
                Section(L("Source Video")) {
                    Text(source.url.lastPathComponent).lineLimit(2)
                    LabeledContent(L("Video Length"), value: wallpaperSeconds(source.duration))
                    LabeledContent(L("Video Size"), value: "\(Int(source.displaySize.width)) × \(Int(source.displaySize.height))")
                }
                Section {
                    wallpaperSlider(L("Clip Start"), value: Binding(get: { wallpaper.clipStart }, set: { wallpaper.setClipStart($0) }),
                                    maximum: wallpaper.maximumClipStart, label: wallpaperSeconds(wallpaper.clipStart))
                    wallpaperSlider(L("Clip Length"), value: Binding(get: { wallpaper.clipDuration }, set: { wallpaper.setClipDuration($0) }),
                                    minimum: 0.5, maximum: wallpaper.maximumClipDuration, label: wallpaperSeconds(wallpaper.clipDuration))
                    wallpaperSlider(L("Cover Frame"), value: Binding(get: { wallpaper.coverTime }, set: { wallpaper.setCoverTime($0) }),
                                    maximum: wallpaper.maximumCoverTime, label: wallpaperSeconds(wallpaper.coverTime))
                } header: {
                    Text(L("Selected Clip"))
                } footer: {
                    Text(L("Select 0.5–3 seconds. The cover frame is measured from the clip start. The exported Live Photo is silent."))
                }
                .disabled(wallpaper.isBusy)
                Section(L("Portrait Framing")) {
                    Picker(L("Screen Shape"), selection: $wallpaper.format) {
                        Text(L("Modern iPhone (19.5:9)")).tag(WallpaperFormat.modernPhone)
                        Text(L("Classic iPhone (16:9)")).tag(WallpaperFormat.classicPhone)
                    }
                    wallpaperSlider(L("Zoom"), value: $wallpaper.zoom, minimum: 1, maximum: 3,
                                    label: String(format: "%.2f×", wallpaper.zoom))
                    wallpaperSlider(L("Horizontal Position"), value: $wallpaper.horizontalPosition, minimum: -1, maximum: 1)
                    wallpaperSlider(L("Vertical Position"), value: $wallpaper.verticalPosition, minimum: -1, maximum: 1)
                    Button(L("Reset Framing")) { wallpaper.resetFraming() }
                    Text(L("Output: %@ · HEVC · 60 fps", "\(Int(wallpaper.format.size.width)) × \(Int(wallpaper.format.size.height))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(wallpaper.isBusy)
            }
            Section {
                Text(L("1. Create the Live Photo and save it to Mac Photos."))
                Text(L("2. Sync it to your iPhone using iCloud Photos, or share the Live Photo from Photos using AirDrop. Check that it arrives as one Live Photo."))
                Text(L("3. On iPhone, open Settings > Wallpaper > Add New Wallpaper > Photos > Live Photo, and enable playback."))
                Text(L("If iPhone says motion is unavailable, this Live Photo cannot currently be used as a motion wallpaper. Mac preview playback does not confirm Lock Screen support."))
                    .foregroundStyle(.secondary)
                Link(L("Apple Live Photo Wallpaper Guide"), destination: URL(string: "https://support.apple.com/120734")!)
            } header: {
                Text(L("Use on iPhone"))
            } footer: {
                Text(L("Exported JPEG and MOV files are the original pair for backup. Sending them separately may create a photo and a video instead of one Live Photo."))
            }
        }
        .formStyle(.grouped)
    }

    private func wallpaperSlider(_ title: String, value: Binding<Double>, minimum: Double = 0,
                                  maximum: Double, label: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                if let label { Text(label).monospacedDigit().foregroundStyle(.secondary) }
            }
            Slider(value: value, in: minimum...max(minimum + 0.0001, maximum))
                .disabled(maximum <= minimum)
                .accessibilityLabel(title)
        }
    }

    private func wallpaperSeconds(_ value: Double) -> String {
        L("%@ s", String(format: "%.2f", value))
    }

    func openVideoPicker() {
        guard !wallpaper.isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("Choose a video for your Live Photo wallpaper.")
        if panel.runModal() == .OK, let url = panel.url { wallpaper.load(url) }
    }

    func openLivePhotoExportPanel() {
        guard wallpaper.canExport else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Export")
        panel.message = L("Choose a folder. FaceLift creates a new subfolder containing the paired JPEG and MOV files.")
        if panel.runModal() == .OK, let url = panel.url { wallpaper.export(to: url) }
    }
}
