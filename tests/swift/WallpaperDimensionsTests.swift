import Foundation
import AVFoundation
import ImageIO

// Model state tests do not need the application's language singleton.
@MainActor func L(_ key: String, _ args: String...) -> String { key }

@main
struct WallpaperDimensionsTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        try LivePhotoConverterTests.require(condition(), message)
    }

    @MainActor static func main() async throws {
        let widths = WallpaperResolution.allCases.map(\.rawValue)
        try require(widths == widths.sorted(by: >), "resolution choices must descend")
        for format in WallpaperFormat.allCases {
            for preset in WallpaperResolution.allCases {
                let size = preset.size(for: format)
                try require(Int(size.width) % 2 == 0 && Int(size.height) % 2 == 0, "HEVC dimensions must be even")
                try require(abs(size.height - size.width * format.heightToWidth) <= 1, "screen shape lost")
            }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FaceLift-DimensionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let url = temporary.appendingPathComponent("source.mov")
        try LivePhotoConverterTests.fixture(at: url, rotated: true)
        let source = try await LivePhotoConverter.inspect(url)
        let cases: [(WallpaperFormat, WallpaperResolution, CGSize)] = [
            (.modernPhone, .ultra, CGSize(width: 2160, height: 4680)),
            (.modernPhone, .fullHD, CGSize(width: 1080, height: 2340)),
            (.modernPhone, .hd, CGSize(width: 720, height: 1560)),
            (.classicPhone, .hd, CGSize(width: 720, height: 1280))
        ]
        for (format, resolution, expectedSize) in cases {
            fputs("Encoding resolution: \(expectedSize)\n", stderr)
            let request = WallpaperConversionRequest(source: source, start: 0, duration: 0.5, coverTime: 0.25,
                format: format, resolution: resolution, zoom: 1, horizontalPosition: 0, verticalPosition: 0)
            let result = try await LivePhotoConverter.convert(request, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
            defer { result.removeTemporaryFiles() }
            let movie = AVURLAsset(url: result.videoURL)
            let track = try await movie.loadTracks(withMediaType: .video)[0]
            let size = try await track.load(.naturalSize)
            try require(size == expectedSize, "selected resolution not encoded: \(size)")
            let frames = try await LivePhotoConverterTests.frameTimes(of: result.videoURL)
            try require(frames.count == 30, "expected 30 encoded frames for half a second")
            let imageSource = CGImageSourceCreateWithURL(result.photoURL as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
            try require(image.width == Int(size.width) && image.height == Int(size.height), "cover and video dimensions differ")
            try require(result.videoURL.lastPathComponent.contains("\(Int(size.width))x\(Int(size.height))"), "filename must identify resolution")
            let metadataTracks = try await movie.loadTracks(withMediaType: .metadata)
            try require(metadataTracks.count == 2, "wallpaper metadata tracks missing")
        }
        let model = VideoWallpaperModel()
        fputs("Testing model resolution changes\n", stderr)
        try require(model.resolution == .fullHD, "default resolution changed")
        model.setResolution(.width984)
        model.load(url, suggestedFormat: .modernPhone)
        model.setResolution(.compact)
        try require(model.resolution == .width984, "resolution changed while loading")
        for _ in 0..<100 {
            if !model.isBusy { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try require(model.source != nil, "model did not load video")
        try require(model.resolution == .width984, "device suggestion replaced user resolution")
        try require(model.outputSize == CGSize(width: 984, height: 2132), "model output does not reflect selection")
        model.setResolution(.hd)
        try require(model.outputSize == CGSize(width: 720, height: 1560), "resolution downgrade ignored")
        model.format = .classicPhone
        try require(model.outputSize == CGSize(width: 720, height: 1280), "shape change lost resolution selection")
        model.clear()
        print("ok: descending presets, even dimensions, HEVC encoding at four sizes, matching covers, paired metadata, model selection and busy guards")
    }
}
