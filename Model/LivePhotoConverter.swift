import Foundation
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Photos

/// Cancellation also reaches the synchronous reader/writer worker. The main
/// actor never waits on video decoding, encoding or filesystem copies.
private final class WallpaperCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

enum LivePhotoConverter {
    static func inspect(_ url: URL) async throws -> WallpaperVideoSource {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= WallpaperConversionRequest.minimumDuration,
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw WallpaperConversionError.invalidVideo
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let result = WallpaperVideoSource(url: url, duration: duration, naturalSize: size, preferredTransform: transform)
        guard result.displaySize.width > 0, result.displaySize.height > 0 else {
            throw WallpaperConversionError.invalidVideo
        }
        return result
    }

    static func composition(for request: WallpaperConversionRequest, renderSize: CGSize? = nil) async throws
        -> (AVMutableComposition, AVMutableVideoComposition) {
        try request.validate()
        let source = AVURLAsset(url: request.source.url)
        guard let sourceTrack = try await source.loadTracks(withMediaType: .video).first else {
            throw WallpaperConversionError.invalidVideo
        }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WallpaperConversionError.invalidVideo
        }
        try track.insertTimeRange(request.timeRange, of: sourceTrack, at: .zero)
        let size = renderSize ?? request.format.size
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(request.cropTransform(renderSize: size), at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: request.timeRange.duration)
        instruction.layerInstructions = [layer]
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: WallpaperConversionRequest.frameRate)
        videoComposition.instructions = [instruction]
        // Normalize HDR inputs to SDR, giving the JPEG cover and movie matching colors.
        videoComposition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        videoComposition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        videoComposition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        return (composition, videoComposition)
    }

    static func convert(_ request: WallpaperConversionRequest,
                        metadataTemplateURL: URL? = nil,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> GeneratedLivePhoto {
        guard let templateURL = metadataTemplateURL ?? Bundle.main.url(forResource: "WallpaperMetadata", withExtension: "mov", subdirectory: "LivePhoto") else {
            throw WallpaperConversionError.encoding("Missing wallpaper metadata resource. Rebuild or reinstall FaceLift.")
        }
        let (asset, videoComposition) = try await composition(for: request)
        try Task.checkCancellation()
        let cancellation = WallpaperCancellation()
        return try await withTaskCancellationHandler {
            let generated: GeneratedLivePhoto = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try encode(request, asset: asset, videoComposition: videoComposition,
                                                templateURL: templateURL, cancellation: cancellation, progress: progress)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            do {
                try Task.checkCancellation()
                try await validate(generated)
                try Task.checkCancellation()
                progress(1)
                return generated
            } catch {
                generated.removeTemporaryFiles()
                throw error
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func encode(_ request: WallpaperConversionRequest,
                               asset: AVMutableComposition, videoComposition: AVMutableVideoComposition,
                               templateURL: URL, cancellation: WallpaperCancellation,
                               progress: @escaping @Sendable (Double) -> Void) throws -> GeneratedLivePhoto {
        let identifier = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FaceLift-LivePhoto-\(identifier)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let result = GeneratedLivePhoto(directory: directory,
                                        photoURL: directory.appendingPathComponent("Wallpaper.jpg"),
                                        videoURL: directory.appendingPathComponent("Wallpaper.mov"), identifier: identifier)
        var completed = false
        defer { if !completed { result.removeTemporaryFiles() } }
        try cancellation.check()

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: asset.tracks(withMediaType: .video),
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.videoComposition = videoComposition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw WallpaperConversionError.invalidVideo }
        reader.add(output)

        let writer = try AVAssetWriter(outputURL: result.videoURL, fileType: .mov)
        let contentID = AVMutableMetadataItem()
        contentID.identifier = .quickTimeMetadataContentIdentifier
        contentID.dataType = kCMMetadataBaseDataType_UTF8 as String
        contentID.value = identifier as NSString
        writer.metadata = [contentID]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(request.format.size.width),
            AVVideoHeightKey: Int(request.format.size.height),
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000,
                                              AVVideoExpectedSourceFrameRateKey: Int(WallpaperConversionRequest.frameRate),
                                              AVVideoMaxKeyFrameIntervalKey: Int(WallpaperConversionRequest.frameRate)]
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw WallpaperConversionError.encoding("Video track unavailable") }
        writer.add(input)

        // Preserve the template's private format description (including setup data),
        // not just the live-photo-info key. Its constant payload is used by the
        // referenced wallpaper converter; it is not sensor data from this video.
        let template = AVURLAsset(url: templateURL)
        guard let motionTrack = template.tracks(withMediaType: .metadata).first(where: { track in
            track.formatDescriptions.contains { description in
                let identifiers = CMMetadataFormatDescriptionGetIdentifiers(description as! CMFormatDescription) as? [String] ?? []
                return identifiers.contains("mdta/com.apple.quicktime.live-photo-info")
            }
        }) else { throw WallpaperConversionError.encoding("Wallpaper motion metadata missing") }
        let templateReader = try AVAssetReader(asset: template)
        let templateOutput = AVAssetReaderTrackOutput(track: motionTrack, outputSettings: nil)
        templateReader.add(templateOutput)
        guard templateReader.startReading() else {
            throw WallpaperConversionError.encoding("Cannot start wallpaper metadata reader")
        }
        // The leading empty edit can appear as a sample without a format.
        var firstMotionSample: CMSampleBuffer?
        while let sample = templateOutput.copyNextSampleBuffer() {
            if CMSampleBufferGetFormatDescription(sample) != nil, CMSampleBufferGetTotalSampleSize(sample) > 0 {
                firstMotionSample = sample
                break
            }
        }
        guard let motionSample = firstMotionSample,
              let motionDescription = CMSampleBufferGetFormatDescription(motionSample) else {
            throw WallpaperConversionError.encoding("Cannot read wallpaper motion metadata")
        }
        templateReader.cancelReading()
        let motionInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: motionDescription)
        guard writer.canAdd(motionInput) else { throw WallpaperConversionError.encoding("Motion metadata track unavailable") }
        writer.add(motionInput)

        // Cover time and the identity transform share one native-style track.
        var description: CMFormatDescription?
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String
        ]
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault,
            metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [specification, [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.live-photo-still-image-transform",
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.perspective-transform-float64"
            ]] as CFArray,
            formatDescriptionOut: &description)
        guard status == noErr, let description else { throw WallpaperConversionError.imageCreation }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        guard writer.canAdd(metadataInput) else { throw WallpaperConversionError.encoding("Metadata track unavailable") }
        writer.add(metadataInput)

        guard writer.startWriting(), reader.startReading() else {
            writer.cancelWriting(); reader.cancelReading()
            throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "Cannot start encoding")
        }
        writer.startSession(atSourceTime: .zero)
        defer {
            if !completed { reader.cancelReading(); writer.cancelWriting() }
        }
        let marker = AVMutableMetadataItem()
        marker.keySpace = .quickTimeMetadata
        marker.key = "com.apple.quicktime.still-image-time" as NSString
        marker.dataType = kCMMetadataBaseDataType_SInt8 as String
        marker.value = NSNumber(value: Int8(-1))
        let transform = AVMutableMetadataItem()
        transform.identifier = AVMetadataIdentifier(rawValue: "mdta/com.apple.quicktime.live-photo-still-image-transform")
        transform.dataType = "com.apple.metadata.perspective-transform-float64"
        transform.value = [1.0, 0, 0, 0, 1, 0, 0, 0, 1] as NSArray
        try waitUntilReady(metadataInput, writer: writer, cancellation: cancellation)
        guard adaptor.append(AVTimedMetadataGroup(items: [marker, transform], timeRange:
            CMTimeRange(start: request.coverTimestamp, duration: CMTimeMinimum(CMTime(value: 1, timescale: 600),
                CMTimeSubtract(request.timeRange.duration, request.coverTimestamp))))) else {
            throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? "Cannot write cover marker")
        }
        metadataInput.markAsFinished()

        var frames = 0
        var currentSample = output.copyNextSampleBuffer()
        while let sample = currentSample {
            try cancellation.check()
            let nextSample = output.copyNextSampleBuffer()
            let intervalEnd = nextSample.map(CMSampleBufferGetPresentationTimeStamp) ?? request.timeRange.duration
            // A composition reader can omit identical intermediate renders.
            // Resample explicitly; setting ExpectedSourceFrameRate alone does
            // not turn a 24/30 fps source into an actual 60 fps movie.
            while CMTime(value: Int64(frames), timescale: WallpaperConversionRequest.frameRate) < intervalEnd {
                try cancellation.check()
                let timestamp = CMTime(value: Int64(frames), timescale: WallpaperConversionRequest.frameRate)
                if timestamp >= request.timeRange.duration { break }
                let frameDuration = CMTimeMinimum(CMTime(value: 1, timescale: WallpaperConversionRequest.frameRate),
                                                  CMTimeSubtract(request.timeRange.duration, timestamp))
                var timing = CMSampleTimingInfo(duration: frameDuration,
                    presentationTimeStamp: timestamp, decodeTimeStamp: .invalid)
                var videoSample: CMSampleBuffer?
                let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                    sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                    sampleBufferOut: &videoSample)
                guard status == noErr, let videoSample else {
                    throw WallpaperConversionError.encoding("Cannot resample video frame")
                }
                try waitUntilReady(input, writer: writer, cancellation: cancellation)
                guard input.append(videoSample) else {
                    throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? "Cannot encode frame")
                }
                // Match the compatible template's 0.05s lead-in, then one
                // metadata sample per output frame, even for shorter clips.
                if timestamp.seconds >= 0.05 {
                    var timedSample: CMSampleBuffer?
                    let status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                        sampleBuffer: motionSample, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                        sampleBufferOut: &timedSample)
                    guard status == noErr, let timedSample else {
                        throw WallpaperConversionError.encoding("Cannot retime wallpaper metadata")
                    }
                    try waitUntilReady(motionInput, writer: writer, cancellation: cancellation)
                    guard motionInput.append(timedSample) else {
                        throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? "Cannot write motion metadata")
                    }
                }
                frames += 1
                progress(min(0.9, timestamp.seconds / request.duration * 0.9))
            }
            currentSample = nextSample
        }
        guard reader.status == .completed, frames > request.coverFrame else {
            throw WallpaperConversionError.encoding(reader.error?.localizedDescription ?? "Incomplete video")
        }
        input.markAsFinished()
        motionInput.markAsFinished()
        writer.endSession(atSourceTime: request.timeRange.duration)
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        // The worker owns the files until finishWriting returns, including cancellation.
        guard finished.wait(timeout: .now() + 60) == .success else {
            throw WallpaperConversionError.encoding("Encoder timed out")
        }
        try cancellation.check()
        guard writer.status == .completed else {
            throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? "Cannot finalize video")
        }
        progress(0.93)
        // Extract from the finished movie, so the cover has exactly the same crop,
        // rotation and color conversion as the paired video.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: result.videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try generator.copyCGImage(at: request.coverTimestamp, actualTime: nil)
        guard let destination = CGImageDestinationCreateWithURL(result.photoURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw WallpaperConversionError.imageCreation
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyMakerAppleDictionary: ["17": identifier]
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperConversionError.imageCreation }
        try cancellation.check()
        completed = true
        return result
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput, writer: AVAssetWriter,
                                       cancellation: WallpaperCancellation) throws {
        let deadline = Date().addingTimeInterval(30)
        while !input.isReadyForMoreMediaData {
            try cancellation.check()
            guard writer.status == .writing, Date() < deadline else {
                throw WallpaperConversionError.encoding(writer.error?.localizedDescription ?? "Encoder stalled")
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    static func validate(_ result: GeneratedLivePhoto) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHLivePhoto.request(withResourceFileURLs: [result.photoURL, result.videoURL], placeholderImage: nil,
                                targetSize: CGSize(width: 270, height: 585), contentMode: .aspectFit) { photo, info in
                if (info[PHLivePhotoInfoIsDegradedKey] as? Bool) == true { return }
                if photo != nil {
                    continuation.resume()
                } else {
                    let message = (info[PHLivePhotoInfoErrorKey] as? Error)?.localizedDescription ?? "Invalid photo/video pair"
                    continuation.resume(throwing: WallpaperConversionError.invalidLivePhoto(message))
                }
            }
        }
    }

    static func saveToPhotos(_ result: GeneratedLivePhoto) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw WallpaperConversionError.photosPermission }
        guard PHAssetCreationRequest.supportsAssetResourceTypes([
            NSNumber(value: PHAssetResourceType.photo.rawValue), NSNumber(value: PHAssetResourceType.pairedVideo.rawValue)
        ]) else { throw WallpaperConversionError.photosUnsupported }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .photo, fileURL: result.photoURL, options: nil)
                creation.addResource(with: .pairedVideo, fileURL: result.videoURL, options: nil)
            }
        } catch {
            throw WallpaperConversionError.photosSave(error.localizedDescription)
        }
    }
}
