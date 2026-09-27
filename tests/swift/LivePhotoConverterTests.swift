import Foundation
import AVFoundation
import ImageIO
import VideoToolbox

#if !WALLPAPER_DIMENSION_TESTS
@main
#endif
struct LivePhotoConverterTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "LivePhotoTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func fixture(at url: URL, rotated: Bool = false) throws {
        // A temporal change in the green channel catches covers extracted
        // from the source's wrong time instead of the selected clip.
        try fixture(at: url, times: (0..<60).map { CMTime(value: Int64($0), timescale: 30) },
                    end: CMTime(seconds: 2, preferredTimescale: 30), rotated: rotated) { x, frame in
            (x < 160 ? 0 : 220, UInt8(frame * 3), x < 160 ? 220 : 0)
        }
    }

    /// Writes 320×180 frames at the given presentation times. `pixel` returns
    /// the BGR value for column `x` of frame `frame`. `hlg` tags the movie as
    /// BT.2020 HLG, the format of HDR iPhone recordings.
    static func fixture(at url: URL, times: [CMTime], end: CMTime, rotated: Bool = false, hlg: Bool = false,
                        pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var settings: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180]
        if hlg {
            // iPhone HDR recordings are 10-bit HEVC tagged BT.2020 HLG.
            settings[AVVideoCodecKey] = AVVideoCodecType.hevc
            settings[AVVideoCompressionPropertiesKey] = [AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]
            settings[AVVideoColorPropertiesKey] = [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                                                   AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                                                   AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020]
        }
        try require(writer.canApply(outputSettings: settings, forMediaType: .video), "fixture settings unsupported")
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        if rotated { input.transform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0) }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                                         kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        try require(writer.startWriting(), "fixture writer failed")
        writer.startSession(atSourceTime: .zero)
        for (frame, time) in times.enumerated() {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
            var buffer: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else {
                throw NSError(domain: "LivePhotoTests", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "fixture pixel pool unavailable (HLG=\(hlg)): \(writer.error?.localizedDescription ?? "unknown")"])
            }
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            try require(status == kCVReturnSuccess && buffer != nil, "fixture pixel allocation failed: \(status)")
            let pixelBuffer = buffer!
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let base = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0..<180 {
                for x in 0..<320 {
                    let i = y * stride + x * 4
                    let (blue, green, red) = pixel(x, frame)
                    base[i] = blue
                    base[i + 1] = green
                    base[i + 2] = red
                    base[i + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            try require(adaptor.append(pixelBuffer, withPresentationTime: time),
                        "fixture append failed (HLG=\(hlg)): \(writer.error?.localizedDescription ?? "unknown")")
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: end)
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        try require(writer.status == .completed, "fixture finalize failed")
    }

    /// Averages the cover to one pixel and returns its RGBA bytes.
    static func coverPixel(_ result: GeneratedLivePhoto) throws -> [UInt8] {
        let imageSource = CGImageSourceCreateWithURL(result.photoURL as CFURL, nil)!
        return averagePixel(CGImageSourceCreateImageAtIndex(imageSource, 0, nil)!)
    }

    static func averagePixel(_ image: CGImage) -> [UInt8] {
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: 4)
        defer { bytes.deallocate() }
        let context = CGContext(data: bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(UnsafeBufferPointer(start: bytes, count: 4))
    }

    /// Presentation times of every encoded frame, in display order.
    static func frameTimes(of url: URL) async throws -> [CMTime] {
        let movie = AVURLAsset(url: url)
        let track = try await movie.loadTracks(withMediaType: .video)[0]
        let reader = try AVAssetReader(asset: movie)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        try require(reader.startReading(), "cannot read output video")
        var times: [CMTime] = []
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { times.append(CMSampleBufferGetPresentationTimeStamp(sample)) }
        }
        try require(reader.status == .completed, "output video decoding failed")
        return times.sorted { CMTimeCompare($0, $1) < 0 }
    }

    static func transferFunction(of url: URL) async throws -> String? {
        let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)[0]
        let descriptions = try await track.load(.formatDescriptions)
        return CMFormatDescriptionGetExtension(descriptions[0],
            extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
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
        let bounds = CGRect(origin: .zero, size: source.naturalSize).applying(request.cropTransform(renderSize: request.outputSize))
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
        try require(videoSize == request.outputSize, "output dimensions incorrect")
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
        try require(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent(result.videoURL.lastPathComponent).path), "pair export incomplete")
        // Exporting again to the same folder keeps the first pair and adds a suffix.
        let secondExport = try result.export(to: temporary)
        try require(secondExport != exportURL && secondExport.lastPathComponent == exportURL.lastPathComponent + "-2",
                    "second export should use a new numbered folder: \(secondExport.lastPathComponent)")
        try require(FileManager.default.fileExists(atPath: exportURL.appendingPathComponent(result.photoURL.lastPathComponent).path)
                    && FileManager.default.fileExists(atPath: secondExport.appendingPathComponent(result.videoURL.lastPathComponent).path),
                    "repeated export overwrote or lost files")

        let rotatedURL = temporary.appendingPathComponent("portrait.mov")
        try fixture(at: rotatedURL, rotated: true)
        let rotated = try await LivePhotoConverter.inspect(rotatedURL)
        try require(rotated.displaySize == CGSize(width: 180, height: 320), "portrait orientation lost")
        request = WallpaperConversionRequest(source: rotated, start: 0, duration: 0.5, coverTime: 0.2,
            format: .modernPhone, resolution: .hd, zoom: 1.2, horizontalPosition: 1, verticalPosition: -1)
        let rotatedResult = try await LivePhotoConverter.convert(request, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let modernTrack = try await AVURLAsset(url: rotatedResult.videoURL).loadTracks(withMediaType: .video)[0]
        let modernSize = try await modernTrack.load(.naturalSize)
        try require(modernSize == CGSize(width: 720, height: 1560), "modern wallpaper exceeds verified animation dimensions")
        let modernCover = CGImageSourceCreateWithURL(rotatedResult.photoURL as CFURL, nil)!
        let modernImage = CGImageSourceCreateImageAtIndex(modernCover, 0, nil)!
        try require(modernImage.width == 720 && modernImage.height == 1560, "modern cover must match paired movie dimensions")
        rotatedResult.removeTemporaryFiles()

        // Variable frame rate: irregular source timing must still become a
        // constant 60 fps timeline, and the cover must be the source frame on
        // screen at the cover time (the one starting at 0.45 s for 0.5 s).
        let vfrURL = temporary.appendingPathComponent("variable.mov")
        let vfrTimes = [0, 0.04, 0.13, 0.2, 0.33, 0.45, 0.55, 0.71, 0.8]
        // Neutral gray levels survive color conversion without hue shifts.
        try fixture(at: vfrURL, times: vfrTimes.map { CMTime(seconds: $0, preferredTimescale: 600) },
                    end: CMTime(seconds: 1, preferredTimescale: 600)) { _, frame in
            let level = UInt8(20 + frame * 25)
            return (level, level, level)
        }
        let vfr = try await LivePhotoConverter.inspect(vfrURL)
        let vfrRequest = WallpaperConversionRequest(source: vfr, start: 0, duration: 1, coverTime: 0.5,
            format: .classicPhone, zoom: 1, horizontalPosition: 0, verticalPosition: 0)
        let vfrResult = try await LivePhotoConverter.convert(vfrRequest, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { vfrResult.removeTemporaryFiles() }
        let vfrFrames = try await frameTimes(of: vfrResult.videoURL)
        try require(vfrFrames.count == 60, "variable frame rate source did not produce 60 frames: \(vfrFrames.count)")
        for (index, time) in vfrFrames.enumerated() {
            try require(CMTimeCompare(time, CMTime(value: Int64(index), timescale: 60)) == 0,
                        "output frame \(index) is not on the 60 fps grid: \(time.seconds)")
        }
        // Decode each source frame as a reference instead of assuming exact
        // levels after encoding; the cover must be nearest the 0.45 s frame.
        let referenceGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: vfrURL))
        referenceGenerator.requestedTimeToleranceBefore = .zero
        referenceGenerator.requestedTimeToleranceAfter = .zero
        let references: [Int] = try vfrTimes.map { time in
            let image = try referenceGenerator.copyCGImage(at: CMTime(seconds: time + 0.01, preferredTimescale: 600), actualTime: nil)
            return Int(averagePixel(image)[1])
        }
        let vfrCover = try Int(coverPixel(vfrResult)[1])
        let nearest = references.indices.min { abs(references[$0] - vfrCover) < abs(references[$1] - vfrCover) }!
        try require(nearest == 5, "variable frame rate cover \(vfrCover) matches source frame \(nearest), not the 0.45 s frame; references \(references)")

        // HDR: HLG input is normalized to SDR Rec.709 without clipping a
        // mid-level signal to black or white.
        let hdrURL = temporary.appendingPathComponent("hlg.mov")
        try fixture(at: hdrURL, times: (0..<30).map { CMTime(value: Int64($0), timescale: 30) },
                    end: CMTime(value: 30, timescale: 30), hlg: true) { _, _ in (128, 128, 128) }
        let hdrInput = try await transferFunction(of: hdrURL)
        try require(hdrInput == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String),
                    "HDR fixture is not tagged HLG: \(hdrInput ?? "none")")
        let hdr = try await LivePhotoConverter.inspect(hdrURL)
        let hdrRequest = WallpaperConversionRequest(source: hdr, start: 0, duration: 0.5, coverTime: 0.25,
            format: .classicPhone, zoom: 1, horizontalPosition: 0, verticalPosition: 0)
        let hdrResult = try await LivePhotoConverter.convert(hdrRequest, metadataTemplateURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { hdrResult.removeTemporaryFiles() }
        let hdrOutput = try await transferFunction(of: hdrResult.videoURL)
        try require(hdrOutput == (kCMFormatDescriptionTransferFunction_ITU_R_709_2 as String),
                    "HDR output is not SDR Rec.709: \(hdrOutput ?? "none")")
        let hdrCover = try coverPixel(hdrResult)
        try require(hdrCover[0...2].allSatisfy { (40...230).contains($0) }, "HDR cover is clipped: \(hdrCover)")

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
        print("ok: crop, clip timing, cover pixels, paired identifiers, wallpaper motion metadata, native cover transform, HEVC/60fps, Live Photo validation, rotation, variable frame rate, HDR to SDR, export, repeated export, cancellation")
    }
}
