import Foundation
import AVFoundation
import ImageIO

@main
struct LivePhotoConverterTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "LivePhotoTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func fixture(at url: URL, rotated: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180
        ])
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        try require(writer.startWriting(), "fixture writer failed")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            let pixelBuffer = buffer!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<180 {
                for x in 0..<320 {
                    let i = y * stride + x * 4
                    // A temporal change in the green channel catches covers extracted
                    // from the source's wrong time instead of the selected clip.
                    base[i] = x < 160 ? 0 : 220
                    base[i + 1] = UInt8(frame * 3)
                    base[i + 2] = x < 160 ? 220 : 0
                    base[i + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            try require(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)), "fixture append failed")
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 2, preferredTimescale: 30))
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        try require(writer.status == .completed, "fixture finalize failed")
    }

    static func pairDirectories() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("FaceLift-LivePhoto-") })
    }

    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("FaceLift-ConverterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let fixtureURL = temporary.appendingPathComponent("landscape.mov")
        try fixture(at: fixtureURL)
        let source = try await LivePhotoConverter.inspect(fixtureURL)
        try require(abs(source.duration - 2) < 0.01, "source duration incorrect")
        var request = WallpaperConversionRequest(source: source, start: 0.5, duration: 1,
            coverTime: 0.4, format: .classicPhone, zoom: 1, horizontalPosition: -1, verticalPosition: 0)
        let bounds = CGRect(origin: .zero, size: source.naturalSize).applying(request.cropTransform(renderSize: request.format.size))
        try require(abs(bounds.minX) < 0.01 && abs(bounds.height - 1920) < 0.01, "left-aligned fill crop incorrect")
        var invalid = request
        invalid.start = 1.5
        do { try invalid.validate(); throw NSError(domain: "LivePhotoTests", code: 2) }
        catch WallpaperConversionError.invalidSelection { }
        invalid = request; invalid.coverTime = invalid.duration
        do { try invalid.validate(); throw NSError(domain: "LivePhotoTests", code: 3) }
        catch WallpaperConversionError.invalidSelection { }

        let result = try await LivePhotoConverter.convert(request, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { result.removeTemporaryFiles() }
        let movie = AVURLAsset(url: result.videoURL)
        let duration = try await movie.load(.duration)
        try require(abs(duration.seconds - 1) < 0.04, "output duration incorrect")
        let metadata = try await movie.load(.metadata)
        try require(metadata.first(where: { $0.identifier == .quickTimeMetadataContentIdentifier })?.stringValue == result.identifier,
                    "movie content identifier missing")
        let video = try await movie.loadTracks(withMediaType: .video)
        let videoSize = try await video[0].load(.naturalSize)
        try require(videoSize == request.format.size, "output dimensions incorrect")
        let audio = try await movie.loadTracks(withMediaType: .audio)
        try require(audio.isEmpty, "wallpaper should be silent")
        let imageSource = CGImageSourceCreateWithURL(result.photoURL as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)! as NSDictionary
        let maker = properties[kCGImagePropertyMakerAppleDictionary] as? NSDictionary
        try require(maker?["17"] as? String == result.identifier, "photo identifier does not match movie")
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!
        try require(image.width == 1080 && image.height == 1920, "cover dimensions incorrect")
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { bytes.deallocate() }
        let context = CGContext(data: bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        try require(bytes[0] > 150 && bytes[2] < 40, "cover crop is not the red left edge")
        try require(abs(Int(bytes[1]) - 81) < 15, "cover does not match source time 0.5 + 0.4")

        let tracks = try await movie.loadTracks(withMediaType: .metadata)
        try require(tracks.count == 2, "wallpaper motion metadata and cover tracks are required")
        let template = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let templateTracks = try await template.loadTracks(withMediaType: .metadata)
        let templateDescriptions = try await templateTracks[0].load(.formatDescriptions)
        let expectedKeyTable = CMFormatDescriptionGetExtension(templateDescriptions[0], extensionKey: "MetadataKeyTable" as CFString) as! NSDictionary
        var foundCover = false
        var motionPayloads = Set<Data>()
        var motionTimes: [Double] = []
        for track in tracks {
            let reader = try AVAssetReader(asset: movie)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
            try require(reader.startReading(), "cannot read metadata track")
            while let group = adaptor.nextTimedMetadataGroup() {
                for item in group.items {
                    switch item.identifier?.rawValue {
                    case "mdta/com.apple.quicktime.still-image-time":
                        foundCover = true
                        try require(abs(group.timeRange.start.seconds - request.coverTimestamp.seconds) < 0.001,
                                    "cover marker timestamp incorrect")
                        try require(item.numberValue?.int8Value == -1, "native cover marker value missing")
                        let transform = group.items.first { $0.identifier?.rawValue == "mdta/com.apple.quicktime.live-photo-still-image-transform" }
                        try require((transform?.value as? [Double]) == [1, 0, 0, 0, 1, 0, 0, 0, 1],
                                    "cover must have the identity transform after crop baking")
                    case "mdta/com.apple.quicktime.live-photo-info":
                        let descriptions = try await track.load(.formatDescriptions)
                        let keyTable = CMFormatDescriptionGetExtension(descriptions[0], extensionKey: "MetadataKeyTable" as CFString) as? NSDictionary
                        try require(keyTable == expectedKeyTable, "private motion format setup data was lost")
                        try require(item.dataValue?.count == 136, "motion metadata payload truncated")
                        motionPayloads.insert(item.dataValue!)
                        motionTimes.append(group.timeRange.start.seconds)
                        try require(CMTimeRangeGetEnd(group.timeRange).seconds <= duration.seconds + 0.001,
                                    "motion metadata extends past the video")
                    default: break
                    }
                }
            }
            try require(reader.status == .completed, "metadata decoding failed")
        }
        try require(foundCover, "cover marker missing")
        try require(motionPayloads.count == 1 && motionTimes.count == 57, "expected a constant compatible motion payload per frame")
        try require(abs(motionTimes[0] - 0.05) < 0.001 && abs(motionTimes.last! - 59.0 / 60) < 0.001,
                    "motion metadata does not cover the frame timeline")
        let descriptions = try await video[0].load(.formatDescriptions)
        try require(CMFormatDescriptionGetMediaSubType(descriptions[0]) == kCMVideoCodecType_HEVC,
                    "wallpaper video must be HEVC")
        let frameRate = try await video[0].load(.nominalFrameRate)
        try require(abs(frameRate - 60) < 0.1, "wallpaper video must have 60 fps")

        let exportURL = try result.export(to: temporary)
        try require(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent("Wallpaper.mov").path), "pair export incomplete")
        do { _ = try result.export(to: temporary); throw NSError(domain: "LivePhotoTests", code: 4) }
        catch let error as NSError { try require(error.domain == NSCocoaErrorDomain, "export should refuse overwriting") }

        let rotatedURL = temporary.appendingPathComponent("portrait.mov")
        try fixture(at: rotatedURL, rotated: true)
        let rotated = try await LivePhotoConverter.inspect(rotatedURL)
        try require(rotated.displaySize == CGSize(width: 180, height: 320), "portrait orientation lost")
        request = WallpaperConversionRequest(source: rotated, start: 0, duration: 0.5, coverTime: 0.2,
            format: .modernPhone, zoom: 1.2, horizontalPosition: 1, verticalPosition: -1)
        let rotatedResult = try await LivePhotoConverter.convert(request, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        rotatedResult.removeTemporaryFiles()

        let before = try pairDirectories()
        // Pause the encoder after its first frame, so cancellation is tested
        // inside the writer loop even on a fast Mac rather than racing a timer.
        let (started, signal) = AsyncStream<Void>.makeStream()
        let resumeEncoder = DispatchSemaphore(value: 0)
        let task = Task {
            defer { signal.finish() }
            return try await LivePhotoConverter.convert(request, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1])) { _ in
                signal.yield(())
                _ = resumeEncoder.wait(timeout: .now() + 5)
            }
        }
        for await _ in started { break }
        task.cancel()
        resumeEncoder.signal()
        do {
            let unexpected = try await task.value
            unexpected.removeTemporaryFiles()
            throw NSError(domain: "LivePhotoTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "cancellation ignored"])
        } catch is CancellationError { }
        let after = try pairDirectories()
        try require(after == before, "cancelled conversion left temporary files")
        print("ok: crop, clip timing, cover pixels, paired identifiers, wallpaper motion metadata, native cover transform, HEVC/60fps, Live Photo validation, rotation, export, cancellation")
    }
}
