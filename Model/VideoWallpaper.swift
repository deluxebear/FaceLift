import Foundation
import CoreGraphics
import AVFoundation

enum WallpaperFormat: String, CaseIterable, Identifiable {
    case modernPhone, classicPhone
    var id: String { rawValue }
    var size: CGSize {
        switch self {
        case .modernPhone: return CGSize(width: 1080, height: 2340)
        case .classicPhone: return CGSize(width: 1080, height: 1920)
        }
    }
}

struct WallpaperVideoSource {
    let url: URL
    let duration: Double
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform

    var displaySize: CGSize {
        CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized.size
    }
}

struct WallpaperConversionRequest {
    let source: WallpaperVideoSource
    var start: Double
    var duration: Double
    /// Time within the selected clip, not the source movie.
    var coverTime: Double
    var format: WallpaperFormat
    var zoom: Double
    /// -1 places the left/top edge at the crop edge; +1 places the right/bottom edge there.
    var horizontalPosition: Double
    var verticalPosition: Double

    static let frameRate: Int32 = 60
    static let minimumDuration = 0.5
    static let maximumDuration = 3.0

    var timeRange: CMTimeRange {
        CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: duration, preferredTimescale: 600))
    }

    var coverFrame: Int {
        let lastFrame = max(0, Int(ceil(duration * Double(Self.frameRate))) - 1)
        return min(lastFrame, max(0, Int(floor(coverTime * Double(Self.frameRate)))))
    }

    var coverTimestamp: CMTime {
        CMTime(value: Int64(coverFrame), timescale: Self.frameRate)
    }

    func validate() throws {
        let numbers = [start, duration, coverTime, zoom, horizontalPosition, verticalPosition,
                       source.duration, Double(source.naturalSize.width), Double(source.naturalSize.height)]
        guard numbers.allSatisfy(\.isFinite), start >= 0,
              duration >= Self.minimumDuration, duration <= Self.maximumDuration,
              start + duration <= source.duration + 0.001,
              coverTime >= 0, coverTime < duration, zoom >= 1, zoom <= 3,
              abs(horizontalPosition) <= 1, abs(verticalPosition) <= 1,
              source.displaySize.width > 0, source.displaySize.height > 0 else {
            throw WallpaperConversionError.invalidSelection
        }
    }

    /// The same transform drives the preview and the encoded movie. Normalize
    /// rotated tracks before scaling so portrait camera movies never export sideways.
    func cropTransform(renderSize: CGSize) -> CGAffineTransform {
        let bounds = CGRect(origin: .zero, size: source.naturalSize)
            .applying(source.preferredTransform).standardized
        let scale = max(renderSize.width / bounds.width, renderSize.height / bounds.height) * zoom
        let overflowX = max(0, bounds.width * scale - renderSize.width)
        let overflowY = max(0, bounds.height * scale - renderSize.height)
        let x = -overflowX * (horizontalPosition + 1) / 2
        let y = -overflowY * (verticalPosition + 1) / 2
        return source.preferredTransform
            .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: x, y: y))
    }
}

enum WallpaperConversionError: Error {
    case invalidVideo
    case invalidSelection
    case encoding(String)
    case imageCreation
    case invalidLivePhoto(String)
    case photosPermission
    case photosUnsupported
    case photosSave(String)
}

struct GeneratedLivePhoto {
    let directory: URL
    let photoURL: URL
    let videoURL: URL
    let identifier: String

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A new directory per export avoids replacing an existing photo/video pair.
    func export(to parent: URL) throws -> URL {
        let destination = parent.appendingPathComponent("FaceLift-\(identifier.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            try FileManager.default.copyItem(at: photoURL, to: destination.appendingPathComponent(photoURL.lastPathComponent))
            try FileManager.default.copyItem(at: videoURL, to: destination.appendingPathComponent(videoURL.lastPathComponent))
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
