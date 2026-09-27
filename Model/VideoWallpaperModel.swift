import SwiftUI
import AVFoundation

private final class WallpaperTemporaryResources {
    var sourceURL: URL?
    var directory: URL?
    deinit {
        sourceURL?.stopAccessingSecurityScopedResource()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }
}

@MainActor
final class VideoWallpaperModel: ObservableObject {
    enum Operation { case loading, generating, saving, exporting }
    enum ResultState { case generated, saved, exported }

    @Published private(set) var source: WallpaperVideoSource?
    @Published private(set) var clipStart = 0.0
    @Published private(set) var clipDuration = 1.0
    @Published private(set) var coverTime = 0.5
    // Framing edits delete the generated files, so reject them while an
    // operation (such as saving to Photos) may still be reading those files.
    @Published var format: WallpaperFormat = .classicPhone {
        didSet {
            if isBusy { format = oldValue; return }
            if !applyingSuggestedFormat { formatChosenByUser = true }
            draftChanged()
        }
    }
    @Published var zoom = 1.0 {
        didSet { if isBusy { zoom = oldValue } else { draftChanged() } }
    }
    @Published var horizontalPosition = 0.0 {
        didSet { if isBusy { horizontalPosition = oldValue } else { draftChanged() } }
    }
    @Published var verticalPosition = 0.0 {
        didSet { if isBusy { verticalPosition = oldValue } else { draftChanged() } }
    }
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isPlaying = false
    @Published private(set) var previewReady = false
    @Published private(set) var operation: Operation?
    @Published private(set) var progress = 0.0
    @Published private(set) var generated: GeneratedLivePhoto?
    @Published private(set) var resultState: ResultState?
    @Published private(set) var exportedDirectory: URL?
    @Published var errorMessage: String?

    private var task: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var playbackObserver: NSObjectProtocol?
    private var sourceAccess = false
    /// A shape picked by hand wins over the one suggested for the connected iPhone.
    private var formatChosenByUser = false
    private var applyingSuggestedFormat = false
    private let resources = WallpaperTemporaryResources()

    var isBusy: Bool { operation != nil }
    var canGenerate: Bool { source != nil && !isBusy }
    var canSave: Bool { generated != nil && !isBusy && resultState != .saved }
    var canExport: Bool { generated != nil && !isBusy }
    var canCancel: Bool { operation == .loading || operation == .generating }
    /// A generated Live Photo that was neither saved nor exported is lost by
    /// loading another video or clearing the draft.
    var hasUnsavedResult: Bool { generated != nil && resultState == .generated }
    var maximumClipDuration: Double { min(3, source?.duration ?? 3) }
    var maximumClipStart: Double { max(0, (source?.duration ?? 0) - clipDuration) }
    var maximumCoverTime: Double { max(0, clipDuration - 1.0 / Double(WallpaperConversionRequest.frameRate)) }

    var status: String {
        switch operation {
        case .loading: return L("Loading video...")
        case .generating: return L("Creating Live Photo...")
        case .saving: return L("Saving to Photos...")
        case .exporting: return L("Exporting Live Photo files...")
        case nil:
            switch resultState {
            case .generated: return L("Live Photo format validated")
            case .saved: return L("Saved to Mac Photos")
            case .exported: return L("Live Photo files exported")
            case nil: return source == nil ? L("Choose a video to begin") : L("Ready to create Live Photo")
            }
        }
    }

    private var request: WallpaperConversionRequest? {
        guard let source else { return nil }
        return WallpaperConversionRequest(source: source, start: clipStart, duration: clipDuration,
            coverTime: coverTime, format: format, zoom: zoom,
            horizontalPosition: horizontalPosition, verticalPosition: verticalPosition)
    }

    /// `suggestedFormat` matches the connected iPhone's screen; it is ignored
    /// once the user has chosen a screen shape.
    func load(_ url: URL, suggestedFormat: WallpaperFormat? = nil) {
        guard !isBusy else { return }
        clear()
        if let suggestedFormat, !formatChosenByUser, suggestedFormat != format {
            applyingSuggestedFormat = true
            format = suggestedFormat
            applyingSuggestedFormat = false
        }
        operation = .loading
        let access = url.startAccessingSecurityScopedResource()
        task = Task {
            do {
                let video = try await LivePhotoConverter.inspect(url)
                try Task.checkCancellation()
                sourceAccess = access
                resources.sourceURL = access ? url : nil
                source = video
                clipDuration = min(1, video.duration)
                coverTime = min(clipDuration / 2, maximumCoverTime)
                operation = nil
                rebuildPreview()
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                if !(error is CancellationError) { errorMessage = describe(error) }
                operation = nil
            }
            task = nil
        }
    }

    func setClipStart(_ value: Double) {
        guard !isBusy else { return }
        clipStart = min(maximumClipStart, max(0, value))
        draftChanged()
    }

    func setClipDuration(_ value: Double) {
        guard !isBusy else { return }
        clipDuration = min(maximumClipDuration, max(0.5, value))
        clipStart = min(clipStart, maximumClipStart)
        coverTime = min(coverTime, maximumCoverTime)
        draftChanged()
    }

    func setCoverTime(_ value: Double) {
        guard !isBusy else { return }
        coverTime = min(maximumCoverTime, max(0, value))
        invalidateResult()
        pause()
        seekToCover()
    }

    func resetFraming() {
        guard !isBusy else { return }
        zoom = 1
        horizontalPosition = 0
        verticalPosition = 0
    }

    private func draftChanged() {
        invalidateResult()
        rebuildPreview()
    }

    private func invalidateResult() {
        generated?.removeTemporaryFiles()
        generated = nil
        resources.directory = nil
        resultState = nil
        exportedDirectory = nil
    }

    private func rebuildPreview() {
        previewTask?.cancel()
        pause()
        previewReady = false
        guard let request else { return }
        previewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 120_000_000)
                let size = request.format.size.applying(CGAffineTransform(scaleX: 0.5, y: 0.5))
                let (asset, composition) = try await LivePhotoConverter.composition(for: request, renderSize: size)
                try Task.checkCancellation()
                let item = AVPlayerItem(asset: asset)
                item.videoComposition = composition
                let newPlayer = AVPlayer(playerItem: item)
                newPlayer.isMuted = true
                if let playbackObserver { NotificationCenter.default.removeObserver(playbackObserver) }
                playbackObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                    object: item, queue: .main) { [weak self] _ in
                        Task { @MainActor in self?.pause(); self?.seekToCover() }
                    }
                player = newPlayer
                previewReady = true
                seekToCover()
            } catch {
                if !(error is CancellationError) { errorMessage = describe(error) }
            }
        }
    }

    func togglePlayback() {
        guard previewReady, let player else { return }
        if isPlaying {
            pause()
            seekToCover()
        } else {
            isPlaying = true
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard finished, let self, self.isPlaying else { return }
                    self.player?.play()
                }
            }
        }
    }

    func pause() { player?.pause(); isPlaying = false }

    private func seekToCover() {
        guard let request else { return }
        player?.seek(to: request.coverTimestamp, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func generate() {
        guard canGenerate, let request else { return }
        pause()
        invalidateResult()
        progress = 0
        operation = .generating
        task = Task {
            do {
                let result = try await LivePhotoConverter.convert(request) { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard self?.operation == .generating else { return }
                        self?.progress = value
                    }
                }
                generated = result
                resources.directory = result.directory
                progress = 1
                resultState = .generated
            } catch {
                if !(error is CancellationError) { errorMessage = describe(error) }
            }
            operation = nil
            task = nil
        }
    }

    func cancel() { if canCancel { task?.cancel() } }

    func saveToPhotos() {
        guard canSave, let generated else { return }
        operation = .saving
        task = Task {
            do {
                try await LivePhotoConverter.saveToPhotos(generated)
                resultState = .saved
            } catch { errorMessage = describe(error) }
            operation = nil
            task = nil
        }
    }

    func export(to parent: URL) {
        guard canExport, let generated else { return }
        operation = .exporting
        task = Task {
            do {
                exportedDirectory = try await Task.detached(priority: .userInitiated) { try generated.export(to: parent) }.value
                // Exporting after a save should not re-enable saving a duplicate asset.
                if resultState != .saved { resultState = .exported }
            } catch { errorMessage = describe(error) }
            operation = nil
            task = nil
        }
    }

    func clear() {
        guard !isBusy else { return }
        previewTask?.cancel()
        pause()
        player = nil
        previewReady = false
        if let playbackObserver { NotificationCenter.default.removeObserver(playbackObserver) }
        playbackObserver = nil
        if sourceAccess { source?.url.stopAccessingSecurityScopedResource() }
        sourceAccess = false
        resources.sourceURL = nil
        source = nil
        clipStart = 0
        clipDuration = 1
        coverTime = 0.5
        resetFraming()
        invalidateResult()
        errorMessage = nil
    }

    private func describe(_ error: Error) -> String {
        guard let error = error as? WallpaperConversionError else {
            return L("Video operation failed: %@", error.localizedDescription)
        }
        switch error {
        case .invalidVideo: return L("Choose a readable video with at least 0.5 seconds of footage.")
        case .invalidSelection: return L("Choose a clip between 0.5 and 3 seconds and a cover frame inside it.")
        case .encoding(let detail): return L("Could not encode the video: %@", detail)
        case .imageCreation: return L("Could not create the Live Photo cover image.")
        case .invalidLivePhoto(let detail): return L("Live Photo format validation failed: %@", detail)
        case .photosPermission: return L("Allow FaceLift to add photos in System Settings > Privacy & Security > Photos, then try again. You can also export the paired files.")
        case .photosUnsupported: return L("This Photos library cannot create a Live Photo from paired files. Export the files instead.")
        case .photosSave(let detail): return L("Could not save to Photos: %@", detail)
        }
    }

    deinit {
        task?.cancel()
        previewTask?.cancel()
        if let playbackObserver { NotificationCenter.default.removeObserver(playbackObserver) }
    }
}
